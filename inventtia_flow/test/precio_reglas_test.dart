import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/config_precio.dart';
import 'package:inventtia_flow/utils/precio_reserva.dart';

/// Reglas de precio por dato adicional integradas con el precio del turno
/// (F6 / decisión D5):
///
///  1. la base es el precio propio del turno si viene (`baseUnitario`), y si no
///     el `precios_base` del servicio;
///  2. encima se evalúan las reglas en orden: gana la primera **coincidente con
///     precio resoluble**;
///  3. una regla sin precio para la moneda elegida ni para la moneda por
///     defecto se ignora: **nunca** deja el total en 0.
ConfigPrecio _cfg({
  String monedaDefault = 'USD',
  List<String>? monedas,
  Map<String, Object?>? base,
  List<Map<String, dynamic>>? reglas,
}) =>
    ConfigPrecio.fromJson({
      'moneda_default': monedaDefault,
      'monedas': monedas ?? [monedaDefault],
      if (base != null) 'precios_base': base,
      if (reglas != null) 'reglas': reglas,
    });

ResultadoPrecioReserva _calc(
  ConfigPrecio config, {
  Map<String, dynamic> datos = const {},
  String? moneda,
  int cantidad = 1,
  double? baseUnitario,
}) =>
    PrecioReserva.calcular(
      config: config,
      datosAdicionales: datos,
      moneda: moneda,
      cantidad: cantidad,
      baseUnitario: baseUnitario,
    );

void main() {
  group('base del servicio', () {
    test('usa precios_base de la moneda por defecto', () {
      final r = _calc(_cfg(base: {'USD': 40}));
      expect(r.unitario, 40);
      expect(r.total, 40);
      expect(r.moneda, 'USD');
      expect(r.origen, 'base');
      expect(r.siClave, isNull);
    });

    test('respeta la moneda elegida y multiplica por la cantidad', () {
      final r = _calc(
        _cfg(
          monedaDefault: 'USD',
          monedas: ['USD', 'CUP'],
          base: {'USD': 40, 'CUP': 12000},
        ),
        moneda: 'CUP',
        cantidad: 3,
      );
      expect(r.moneda, 'CUP');
      expect(r.unitario, 12000);
      expect(r.total, 36000);
      expect(r.origen, 'base');
    });

    test('cae a la moneda por defecto si la elegida no está en precios_base', () {
      final r = _calc(
        _cfg(
          monedaDefault: 'USD',
          monedas: ['USD', 'CUP'],
          base: {'USD': 40},
        ),
        moneda: 'CUP',
      );
      expect(r.moneda, 'CUP');
      expect(r.unitario, 40);
      expect(r.origen, 'base');
    });

    test('config vacía devuelve 0 con origen sin_config', () {
      final r = _calc(ConfigPrecio.fromJson({}));
      expect(r.total, 0);
      expect(r.unitario, 0);
      expect(r.moneda, 'USD');
      expect(r.origen, 'sin_config');
    });
  });

  group('regla que reemplaza el base', () {
    final config = _cfg(
      base: {'USD': 40},
      reglas: [
        {
          'si_clave': 'tipo',
          'precios_opcion': {
            'vip': {'USD': 70},
          },
        },
      ],
    );

    test('la regla coincidente gana sobre el base', () {
      final r = _calc(config, datos: {'tipo': 'vip'}, cantidad: 2);
      expect(r.unitario, 70);
      expect(r.total, 140);
      expect(r.moneda, 'USD');
      expect(r.origen, 'regla');
      expect(r.siClave, 'tipo');
    });

    test('sin el dato en la reserva se queda en el base', () {
      final r = _calc(config, datos: const {});
      expect(r.unitario, 40);
      expect(r.origen, 'base');
    });

    test('con una opción distinta a la regla se queda en el base', () {
      final r = _calc(config, datos: {'tipo': 'normal'});
      expect(r.unitario, 40);
      expect(r.origen, 'base');
    });
  });

  group('precio del turno como base', () {
    test('sin regla que case: base del turno y origen turno', () {
      final r = _calc(
        _cfg(base: {'USD': 40}),
        baseUnitario: 90,
      );
      expect(r.unitario, 90);
      expect(r.total, 90);
      expect(r.moneda, 'USD');
      expect(r.origen, 'turno');
    });

    test('base del turno con cantidad', () {
      final r = _calc(_cfg(base: {'USD': 40}), baseUnitario: 90, cantidad: 4);
      expect(r.unitario, 90);
      expect(r.total, 360);
      expect(r.origen, 'turno');
    });

    test('el turno manda aunque el servicio tenga precios_base', () {
      final r = _calc(
        _cfg(monedaDefault: 'USD', monedas: ['USD', 'CUP'], base: {
          'USD': 40,
          'CUP': 12000,
        }),
        moneda: 'CUP',
        baseUnitario: 15000,
      );
      expect(r.unitario, 15000);
      expect(r.moneda, 'CUP');
      expect(r.origen, 'turno');
    });

    test('sin precios_base y con turno: origen turno, no sin_config', () {
      final r = _calc(ConfigPrecio.fromJson({}), baseUnitario: 25);
      expect(r.unitario, 25);
      expect(r.origen, 'turno');
    });

    test('base del turno + regla que casa: gana la regla', () {
      final r = _calc(
        _cfg(
          base: {'USD': 40},
          reglas: [
            {
              'si_clave': 'equipaje',
              'precios_opcion': {
                'extra': {'USD': 70},
              },
            },
          ],
        ),
        datos: {'equipaje': 'extra'},
        baseUnitario: 90,
      );
      expect(r.unitario, 70);
      expect(r.total, 70);
      expect(r.origen, 'regla');
      expect(r.siClave, 'equipaje');
    });

    test('base del turno + regla que no casa: gana el turno', () {
      final r = _calc(
        _cfg(
          base: {'USD': 40},
          reglas: [
            {
              'si_clave': 'equipaje',
              'precios_opcion': {
                'extra': {'USD': 70},
              },
            },
          ],
        ),
        datos: {'equipaje': 'normal'},
        baseUnitario: 90,
      );
      expect(r.unitario, 90);
      expect(r.origen, 'turno');
    });
  });

  group('regla sin precio en la moneda elegida (nunca 0)', () {
    test('se ignora y cae al base del servicio', () {
      final r = _calc(
        _cfg(
          monedaDefault: 'USD',
          monedas: ['USD', 'CUP'],
          base: {'USD': 40, 'CUP': 5000},
          reglas: [
            {
              'si_clave': 'tipo',
              'precios_opcion': {
                'vip': {'EUR': 99},
              },
            },
          ],
        ),
        datos: {'tipo': 'vip'},
        moneda: 'CUP',
      );
      expect(r.unitario, 5000);
      expect(r.total, 5000);
      expect(r.moneda, 'CUP');
      expect(r.origen, 'base');
    });

    test('se ignora y cae al base del turno', () {
      final r = _calc(
        _cfg(
          monedaDefault: 'USD',
          monedas: ['USD', 'CUP'],
          base: {'USD': 40},
          reglas: [
            {
              'si_clave': 'tipo',
              'precios_opcion': {
                'vip': {'EUR': 99},
              },
            },
          ],
        ),
        datos: {'tipo': 'vip'},
        moneda: 'CUP',
        baseUnitario: 15000,
      );
      expect(r.unitario, 15000);
      expect(r.total, 15000);
      expect(r.origen, 'turno');
    });

    test('sin moneda en la regla pero con la moneda por defecto: la usa', () {
      final r = _calc(
        _cfg(
          monedaDefault: 'USD',
          monedas: ['USD', 'CUP'],
          base: {'USD': 40, 'CUP': 5000},
          reglas: [
            {
              'si_clave': 'tipo',
              'precios_opcion': {
                'vip': {'USD': 70},
              },
            },
          ],
        ),
        datos: {'tipo': 'vip'},
        moneda: 'CUP',
      );
      expect(r.unitario, 70);
      expect(r.origen, 'regla');
    });

    test('una regla sin precio no bloquea a la siguiente que sí lo tiene', () {
      final r = _calc(
        _cfg(
          base: {'USD': 40},
          reglas: [
            {
              'si_clave': 'tipo',
              'precios_opcion': {
                'vip': {'CUP': 9000},
              },
            },
            {
              'si_clave': 'tipo',
              'precios_opcion': {
                'vip': {'USD': 70},
              },
            },
          ],
        ),
        datos: {'tipo': 'vip'},
      );
      expect(r.unitario, 70);
      expect(r.origen, 'regla');
    });

    test('regla con la opción vacía en precios_opcion se ignora', () {
      final r = _calc(
        _cfg(
          base: {'USD': 40},
          reglas: [
            {
              'si_clave': 'tipo',
              'precios_opcion': {'vip': <String, dynamic>{}},
            },
          ],
        ),
        datos: {'tipo': 'vip'},
      );
      expect(r.unitario, 40);
      expect(r.origen, 'base');
    });
  });

  group('precios guardados como string (paridad con el SQL)', () {
    test('precios_base con string numérico', () {
      final config = ConfigPrecio.fromJson({
        'moneda_default': 'CUP',
        'monedas': ['CUP', 'USD'],
        'precios_base': {'CUP': '1500', 'USD': ' 5.5 '},
      });
      final r = _calc(config, moneda: 'CUP');
      expect(r.unitario, 1500);
      expect(r.origen, 'base');

      final r2 = _calc(config, moneda: 'USD');
      expect(r2.unitario, 5.5);
    });

    test('precios_opcion con string numérico', () {
      final config = ConfigPrecio.fromJson({
        'moneda_default': 'USD',
        'monedas': ['USD'],
        'precios_base': {'USD': 40},
        'reglas': [
          {
            'si_clave': 'tipo',
            'precios_opcion': {
              'vip': {'USD': '70'},
            },
          },
        ],
      });
      final r = _calc(config, datos: {'tipo': 'vip'});
      expect(r.unitario, 70);
      expect(r.origen, 'regla');
    });

    test('un string ilegible se descarta como antes', () {
      final config = ConfigPrecio.fromJson({
        'moneda_default': 'USD',
        'precios_base': {'USD': 'caro'},
      });
      expect(precioBaseDe(config), isNull);
      final r = _calc(config);
      expect(r.total, 0);
      expect(r.origen, 'sin_config');
    });
  });

  group('formato anterior de reglas (opciones + precios compartidos)', () {
    test('sigue aplicándose y ahora también sobre el turno', () {
      final config = ConfigPrecio.fromJson({
        'moneda_default': 'USD',
        'precios_base': {'USD': 40},
        'reglas': [
          {
            'si_clave': 'tipo',
            'opciones': ['vip'],
            'precios': {'USD': 70},
          },
        ],
      });
      final r = _calc(config, datos: {'tipo': 'vip'}, baseUnitario: 90);
      expect(r.unitario, 70);
      expect(r.origen, 'regla');
    });
  });

  group('no rompe el resto del contrato', () {
    test('formatear sigue igual', () {
      expect(PrecioReserva.formatear(40, 'USD'), r'$40');
      expect(PrecioReserva.formatear(2.5, 'USD'), r'$2.50');
      expect(PrecioReserva.formatear(1500, 'CUP'), '1500 CUP');
    });

    test('precioBaseDe y etiquetaPrecioBase siguen igual', () {
      final config = _cfg(monedaDefault: 'CUP', base: {'CUP': 1500});
      expect(precioBaseDe(config)?.precio, 1500);
      expect(etiquetaPrecioBase(config), '1500 CUP');
      expect(precioBaseDe(ConfigPrecio.fromJson({})), isNull);
    });

    test('el valor booleano del dato se compara por su texto', () {
      final config = _cfg(
        base: {'USD': 40},
        reglas: [
          {
            'si_clave': 'seguro',
            'precios_opcion': {
              'true': {'USD': 15},
            },
          },
        ],
      );
      final r = _calc(config, datos: {'seguro': true});
      expect(r.unitario, 15);
      expect(r.origen, 'regla');
    });
  });
}
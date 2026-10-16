import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/config_precio.dart';
import 'package:inventtia_flow/utils/parse_monto.dart';
import 'package:inventtia_flow/utils/precio_reserva.dart';
import 'package:inventtia_flow/utils/precio_turno.dart';

/// Consumidores del precio (F6 / decisión D5).
///
/// El precio propio del turno dejó de sobrescribir el total en las hojas de
/// transporte y en el preview del admin: ahora entra en `PrecioReserva.calcular`
/// como `baseUnitario`, y las reglas por dato adicional se evalúan encima.
///
/// `precioBaseTurno` es la única copia de la resolución de moneda del turno
/// (moneda elegida → moneda por defecto → sin precio propio) que usan
/// `reserva_transporte_sheet.dart`, `admin_reserva_transporte_sheet.dart` y
/// `reservas_screen.dart`. Si divergiera de `flow.calcular_precio_turno`
/// (migración 51), el precio mostrado dejaría de coincidir con el cobrado.
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
  group('precioBaseTurno (resolución de moneda del turno)', () {
    test('usa el precio de la moneda elegida', () {
      expect(
        precioBaseTurno(
          precios: const {'USD': 18, 'CUP': 1500},
          moneda: 'CUP',
          monedaDefault: 'USD',
        ),
        1500,
      );
    });

    test('cae a la moneda por defecto si el turno no tiene la elegida', () {
      expect(
        precioBaseTurno(
          precios: const {'USD': 18},
          moneda: 'CUP',
          monedaDefault: 'USD',
        ),
        18,
      );
    });

    test('sin moneda elegida usa la moneda por defecto', () {
      expect(
        precioBaseTurno(
          precios: const {'USD': 18, 'CUP': 1500},
          monedaDefault: 'USD',
        ),
        18,
      );
    });

    test('turno sin precios (o mapa nulo) → null: la base la pone el servicio',
        () {
      expect(
        precioBaseTurno(precios: const {}, moneda: 'USD', monedaDefault: 'USD'),
        isNull,
      );
      expect(
        precioBaseTurno(precios: null, moneda: 'USD', monedaDefault: 'USD'),
        isNull,
      );
    });

    test('no adivina con `values.first` (paridad con el SQL)', () {
      // El turno solo tiene precio en una moneda que no es la elegida ni la de
      // por defecto: `calcular_precio_turno` no lo resuelve y deja la base al
      // servicio. Antes la app mostraba ese precio "prestado".
      expect(
        precioBaseTurno(
          precios: const {'EUR': 20},
          moneda: 'CUP',
          monedaDefault: 'USD',
        ),
        isNull,
      );
    });

    test('un precio 0 explícito se respeta (no es "sin precio")', () {
      expect(
        precioBaseTurno(
          precios: const {'USD': 0},
          moneda: 'USD',
          monedaDefault: 'USD',
        ),
        0,
      );
    });
  });

  group('turno como base de las reglas (lo que consume la UI)', () {
    test('sin dato que case, se cobra el precio del turno', () {
      final r = _calc(
        _cfg(base: {'USD': 40}),
        baseUnitario: 18,
      );
      expect(r.unitario, 18);
      expect(r.origen, 'turno');
    });

    test('una regla que casa reemplaza al precio del turno', () {
      final r = _calc(
        _cfg(
          base: {'USD': 40},
          reglas: [
            {
              'si_clave': 'tipo',
              'precios_opcion': {
                'vip': {'USD': 90},
              },
            },
          ],
        ),
        datos: const {'tipo': 'vip'},
        baseUnitario: 18,
      );
      expect(r.unitario, 90);
      expect(r.origen, 'regla');
      expect(r.siClave, 'tipo');
    });

    test('regla sin precio en la moneda elegida pero sí en la de por defecto',
        () {
      final r = _calc(
        _cfg(
          monedaDefault: 'USD',
          monedas: ['USD', 'CUP'],
          base: {'CUP': 1500},
          reglas: [
            {
              'si_clave': 'tipo',
              'precios_opcion': {
                'vip': {'USD': 90},
              },
            },
          ],
        ),
        datos: const {'tipo': 'vip'},
        moneda: 'CUP',
        baseUnitario: 1500,
      );
      // La regla se cobra con el respaldo de la moneda por defecto (90 USD).
      expect(r.unitario, 90);
      expect(r.moneda, 'CUP');
      expect(r.origen, 'regla');
    });

    test('regla sin precio en la moneda elegida → base del turno, nunca 0', () {
      final r = _calc(
        _cfg(
          monedaDefault: 'USD',
          monedas: ['USD', 'CUP'],
          reglas: [
            {
              'si_clave': 'tipo',
              // Solo en una moneda que no es la elegida ni la de por defecto:
              // `calcular_precio_con_reglas` ignora la regla y cae a la base.
              'precios_opcion': {
                'vip': {'EUR': 90},
              },
            },
          ],
        ),
        datos: const {'tipo': 'vip'},
        moneda: 'CUP',
        baseUnitario: 1500,
      );
      expect(r.unitario, 1500);
      expect(r.origen, 'turno');
    });

    test('turno sin precio propio → base del servicio', () {
      final r = _calc(
        _cfg(base: {'USD': 40}),
        baseUnitario: null,
      );
      expect(r.unitario, 40);
      expect(r.origen, 'base');
    });

    test('la cantidad multiplica el precio resuelto', () {
      final r = _calc(_cfg(base: {'USD': 40}), baseUnitario: 18, cantidad: 3);
      expect(r.total, 54);
    });
  });

  group('cadena importe tecleado → precio mostrado (punto c)', () {
    test('"1.500" se guarda como 1500 y se cobra 1500 (antes, 1.5)', () {
      final guardado = parseMonto('1.500');
      expect(guardado, 1500);
      final r = _calc(
        _cfg(
          monedaDefault: 'CUP',
          monedas: ['CUP'],
          base: {'CUP': guardado},
        ),
      );
      expect(r.unitario, 1500);
      expect(r.moneda, 'CUP');
    });

    test('un importe ilegible no se convierte en 0', () {
      expect(parseMonto('mil pesos'), isNull);
    });
  });
}

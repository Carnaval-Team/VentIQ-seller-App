// Verifica el parseo del nombre de cliente embebido en observaciones
// (venta por acuerdo / venta desde orden), usado al imprimir y exportar
// operaciones de inventario.
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/utils/operation_client_utils.dart';

void main() {
  group('extractClienteFromObservaciones', () {
    test('venta por acuerdo con total', () {
      expect(
        extractClienteFromObservaciones(
          'Cliente: Karel Duarte Espinosa. Total: \$186300.00. ',
        ),
        'Karel Duarte Espinosa',
      );
    });

    test('nombre con espacio final y observación extra', () {
      expect(
        extractClienteFromObservaciones(
          'Cliente: Ernesto García García . Total: \$186300.00. Ernesto Factura',
        ),
        'Ernesto García García',
      );
    });

    test('venta desde orden (salto de línea)', () {
      expect(
        extractClienteFromObservaciones('Cliente: Juan Perez\nProductos:\n1 x Pan'),
        'Juan Perez',
      );
    });

    test('solo cliente', () {
      expect(extractClienteFromObservaciones('Cliente: Dr. Ramon'), 'Dr. Ramon');
    });

    test('punto final sin total', () {
      expect(extractClienteFromObservaciones('Cliente: Livann.'), 'Livann');
    });

    test('observación sin cliente', () {
      expect(
        extractClienteFromObservaciones('Venta realizada desde app móvil'),
        isNull,
      );
    });

    test('cliente vacío', () {
      expect(
        extractClienteFromObservaciones('Cliente: . Total: \$10.00. '),
        isNull,
      );
    });

    test('nulo', () {
      expect(extractClienteFromObservaciones(null), isNull);
    });
  });

  group('resolveOperationClienteNombre', () {
    test('prefiere el cliente registrado en la venta', () {
      expect(
        resolveOperationClienteNombre({
          'observaciones': 'Cliente: Nombre En Obs. Total: \$10.00. ',
          'detalles': {
            'detalles_especificos': {'nombre_cliente': 'Cliente Registrado'},
          },
        }),
        'Cliente Registrado',
      );
    });

    test('cae a observaciones cuando la venta va sin cliente', () {
      expect(
        resolveOperationClienteNombre({
          'observaciones': 'Cliente: Karel Duarte Espinosa. Total: \$100.00. ',
          'detalles': {
            'detalles_especificos': {
              'id_cliente': null,
              'nombre_cliente': null,
            },
          },
        }),
        'Karel Duarte Espinosa',
      );
    });

    test('operación sin detalles ni cliente', () {
      expect(
        resolveOperationClienteNombre({
          'observaciones': 'Ajuste de inventario',
        }),
        isNull,
      );
    });
  });
}

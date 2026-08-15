// Verifica el parseo del nombre de cliente embebido en observaciones
// (venta por acuerdo / venta desde orden), igual al usado en
// inventory_operations_screen.dart.
import 'package:flutter_test/flutter_test.dart';

final RegExp clienteObsRegex = RegExp(
  r'Cliente:\s*([^\n\r]*?)\s*(?:\.\s*Total\s*:|\.\s*$|[\n\r]|$)',
  caseSensitive: false,
);

String? extractCliente(dynamic observaciones) {
  final obs = observaciones?.toString() ?? '';
  if (obs.isEmpty) return null;
  final nombre = clienteObsRegex.firstMatch(obs)?.group(1)?.trim();
  if (nombre == null || nombre.isEmpty) return null;
  return nombre;
}

void main() {
  test('venta por acuerdo con total', () {
    expect(
      extractCliente('Cliente: Karel Duarte Espinosa. Total: \$186300.00. '),
      'Karel Duarte Espinosa',
    );
  });

  test('nombre con espacio final y observación extra', () {
    expect(
      extractCliente(
        'Cliente: Ernesto García García . Total: \$186300.00. Ernesto Factura',
      ),
      'Ernesto García García',
    );
  });

  test('venta desde orden (salto de línea)', () {
    expect(
      extractCliente('Cliente: Juan Perez\nProductos:\n1 x Pan'),
      'Juan Perez',
    );
  });

  test('solo cliente', () {
    expect(extractCliente('Cliente: Dr. Ramon'), 'Dr. Ramon');
  });

  test('punto final sin total', () {
    expect(extractCliente('Cliente: Livann.'), 'Livann');
  });

  test('observación sin cliente', () {
    expect(extractCliente('Venta realizada desde app móvil'), isNull);
  });

  test('cliente vacío', () {
    expect(extractCliente('Cliente: . Total: \$10.00. '), isNull);
  });

  test('nulo', () {
    expect(extractCliente(null), isNull);
  });
}

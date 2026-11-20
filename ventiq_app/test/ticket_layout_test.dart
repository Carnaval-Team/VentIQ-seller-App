import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/models/product.dart';
import 'package:ventiq_app/money/product_currency_order.dart';
import 'package:ventiq_app/utils/ticket_data.dart';
import 'package:ventiq_app/utils/ticket_layout.dart';

ProductCurrencySeleccion seleccion({
  required String moneda,
  required String precio,
  required String cantidad,
  String tasa = '1',
}) {
  return ProductCurrencySeleccion(
    idLineaCliente: '00000000-0000-4000-8000-0000000000aa',
    idProducto: '101',
    cantidad: cantidad,
    monedaVenta: moneda,
    tipoCobro: 'medio_pago',
    idMedioPago: 1,
    precioUnitarioNativo: precio,
    descuentoManualUnitario: '0',
    snapshotPrecio: const {'tipo': 'general', 'valor_publicado': '1'},
    snapshotTasa: {
      'valor_publicado': tasa,
      'evidencia_publicacion': 'fixture-only',
    },
    ajustesAutomaticos: const [],
  );
}

OrderItem item({
  required int id,
  required String nombre,
  required double precio,
  required double cantidad,
  String ubicacion = 'A-1',
  ProductCurrencySeleccion? sel,
}) {
  return OrderItem(
    id: 'item-$id',
    producto: Product.fromJson({
      'id': id,
      'denominacion': nombre,
      'precio': precio,
    }),
    cantidad: cantidad,
    ubicacionAlmacen: ubicacion,
    precioUnitario: precio,
    seleccion: sel,
  );
}

Order orden(List<OrderItem> items, {String? version}) => Order(
  id: 'o1',
  fechaCreacion: DateTime(2026, 1, 1),
  items: items,
  total: items.fold(0.0, (sum, i) => sum + i.subtotal),
  status: OrderStatus.borrador,
  versionMonetaria: version,
);

String _texto(List<int> bytes) => String.fromCharCodes(bytes);

/// Índice de la primera aparición de [secuencia] en [bytes] a partir de [desde].
int _buscar(List<int> bytes, List<int> secuencia, [int desde = 0]) {
  for (var i = desde; i <= bytes.length - secuencia.length; i++) {
    var igual = true;
    for (var j = 0; j < secuencia.length; j++) {
      if (bytes[i + j] != secuencia[j]) {
        igual = false;
        break;
      }
    }
    if (igual) return i;
  }
  return -1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Generator generator;

  setUpAll(() async {
    generator = Generator(PaperSize.mm58, await CapabilityProfile.load());
  });

  group('datos del ticket', () {
    test('producto-v1: una línea por producto con su subtotal nativo', () {
      final order = orden(
        version: 'producto-v1',
        [
          item(
            id: 1,
            nombre: 'Arroz',
            precio: 100,
            cantidad: 2,
            sel: seleccion(moneda: 'CUP', precio: '100', cantidad: '2'),
          ),
          item(
            id: 2,
            nombre: 'Aceite',
            precio: 1.05,
            cantidad: 3,
            sel: seleccion(
              moneda: 'USD',
              precio: '1.05',
              cantidad: '3',
              tasa: '400',
            ),
          ),
        ],
      );

      final lineas = TicketData.productos(order, dineroLegacy: (c) => '$c');
      expect(lineas.map((l) => l.cantidad), ['2', '3']);
      expect(lineas.map((l) => l.nombre), ['Arroz', 'Aceite']);
      expect(lineas[0].subtotal, '200.00 CUP');
      expect(lineas[1].subtotal, '3.15 USD');
    });

    test('producto-v1: un total por moneda, sin mezclar divisas', () {
      final order = orden(
        version: 'producto-v1',
        [
          item(
            id: 1,
            nombre: 'Arroz',
            precio: 100,
            cantidad: 2,
            sel: seleccion(moneda: 'CUP', precio: '100', cantidad: '2'),
          ),
          item(
            id: 2,
            nombre: 'Aceite',
            precio: 1.05,
            cantidad: 3,
            sel: seleccion(
              moneda: 'USD',
              precio: '1.05',
              cantidad: '3',
              tasa: '400',
            ),
          ),
        ],
      );

      final totales = TicketData.totales(order, pagos: const []);
      expect(totales.map((t) => (t.moneda, t.monto)), [
        ('CUP', '200.00'),
        ('USD', '3.15'),
      ]);
    });

    test('orden anterior: todos los productos y un total en CUP', () {
      final order = orden([
        item(id: 1, nombre: 'Pan', precio: 100, cantidad: 2),
        item(id: 2, nombre: 'Leche', precio: 250, cantidad: 1),
      ]);

      final lineas = TicketData.productos(
        order,
        dineroLegacy: (c) => '\$${c.toStringAsFixed(0)} CUP',
      );
      expect(lineas.length, 2);
      expect(lineas[0].cantidad, '2');
      expect(lineas[0].subtotal, '\$200 CUP');
      expect(lineas[1].subtotal, '\$250 CUP');

      final totales = TicketData.totales(order, pagos: const []);
      expect(totales.single.moneda, 'CUP');
      expect(totales.single.monto, '450');
    });

    test('el pie de la guía de almacén no lleva importes', () {
      expect(TicketData.almacenResumen(3), 'TOT: 3 prod');
      expect(TicketData.almacenResumen(3), isNot(contains('\$')));
    });
  });

  group('bytes ESC/POS', () {
    // Comandos que dejan el área de impresión estrecha o desplazada y que
    // partían el nombre del producto: ESC a 2 (derecha) y ESC $ con posición
    // distinta de 0 (la usa `row()`).
    const alineaDerecha = [0x1B, 0x61, 0x32];

    /// Líneas impresas (sin comandos de control).
    List<String> lineasDe(List<int> bytes) =>
        _texto(bytes)
            .replaceAll(RegExp(r'\x1B\$..'), '')
            .replaceAll(RegExp(r'\x1B[aE@].?'), '')
            .replaceAll('\x1C.', '')
            .split('\n')
            .where((l) => l.isNotEmpty)
            .toList();

    test('producto: cantidad y nombre a la izquierda, subtotal debajo a la derecha',
        () {
      final bytes = TicketLayout.productoBytes(
        generator,
        cantidad: '2',
        nombre: 'Arroz',
        subtotal: '200.00 CUP',
      );
      final lineas = lineasDe(bytes);
      expect(lineas, hasLength(2));
      expect(lineas[0], '2x Arroz');
      // El subtotal queda pegado al margen derecho (32 columnas).
      expect(lineas[1], hasLength(TicketLayout.anchoLinea));
      expect(lineas[1].trimLeft(), '200.00 CUP');
      expect(lineas[1].endsWith('200.00 CUP'), isTrue);
      expect(_buscar(bytes, alineaDerecha), -1);
    });

    test('la línea del producto es byte a byte la de la guía de almacén', () {
      final factura = TicketLayout.productoBytes(
        generator,
        cantidad: '50',
        nombre: 'Diesel',
        subtotal: '5000.00 CUP',
      );
      final guia = TicketLayout.almacenProductoBytes(
        generator,
        cantidad: '50',
        nombre: 'Diesel',
        ubicacion: 'B-7',
      );
      // Hasta el primer salto de línea (la línea de cantidad y nombre).
      List<int> primeraLinea(List<int> b) => b.sublist(0, b.indexOf(0x0A) + 1);
      expect(primeraLinea(factura), primeraLinea(guia));
      // Y va en negrita (ESC E 1), como la guía.
      expect(_buscar(primeraLinea(factura), [0x1B, 0x45, 0x01]), greaterThanOrEqualTo(0));
    });

    test('ninguna línea de producto cambia el área de impresión', () {
      final bytes = TicketLayout.productoBytes(
        generator,
        cantidad: '50',
        nombre: 'Diesel',
        subtotal: '5000.00 CUP',
      );
      expect(_buscar(bytes, alineaDerecha), -1);
      // ESC $ solo con posición 0 (el generador lo antepone a cada línea).
      for (var i = 0; i < bytes.length - 3; i++) {
        if (bytes[i] == 0x1B && bytes[i + 1] == 0x24) {
          expect([bytes[i + 2], bytes[i + 3]], [0, 0]);
        }
      }
      expect(_texto(bytes), contains('50x Diesel'));
    });

    test('producto con nombre largo se imprime completo, sin recortar', () {
      final nombre = 'Producto con un nombre muy largo ${'N' * 40}';
      final texto = _texto(
        TicketLayout.productoBytes(
          generator,
          cantidad: '1',
          nombre: nombre,
          subtotal: '10 CUP',
        ),
      );
      expect(texto, contains('1x $nombre'));
      expect(texto, isNot(contains('...')));
    });

    test('total: etiqueta y monto en la misma línea, sin salto entre ellos', () {
      final bytes = TicketLayout.totalBytes(
        generator,
        moneda: 'USD',
        monto: '3.15',
      );
      final etiqueta = _buscar(bytes, 'TOTAL USD'.codeUnits);
      final monto = _buscar(bytes, '3.15'.codeUnits);
      expect(etiqueta, greaterThanOrEqualTo(0));
      expect(monto, greaterThan(etiqueta));
      expect(bytes.sublist(etiqueta, monto).contains(0x0A), isFalse);
      // Una sola línea de 32 columnas: etiqueta a la izquierda, monto a la
      // derecha.
      final lineas = lineasDe(bytes);
      expect(lineas, hasLength(1));
      expect(lineas.single, hasLength(TicketLayout.anchoLinea));
      expect(lineas.single.startsWith('TOTAL USD'), isTrue);
      expect(lineas.single.endsWith('3.15'), isTrue);
      // Sin row() ni ESC a 2: no deja el área estrecha.
      expect(_buscar(bytes, alineaDerecha), -1);
    });

    test('total con importe largo deja al menos un espacio entre los textos',
        () {
      final linea = TicketLayout.justificada(
        'TOTAL CUP',
        '1 234 567 890 123 456 789 000.00',
      );
      expect(linea, 'TOTAL CUP 1 234 567 890 123 456 789 000.00');
    });

    test('guía de almacén: cantidad, nombre completo y ubicación, sin importes',
        () {
      final nombre = 'Producto con un nombre bastante largo ${'x' * 20}';
      final texto = _texto(
        TicketLayout.almacenProductoBytes(
          generator,
          cantidad: '4',
          nombre: nombre,
          ubicacion: 'B-7',
        ),
      );
      expect(texto, contains('4x $nombre'));
      expect(texto, contains('Ubic: B-7'));
      expect(texto, isNot(contains('CUP')));
      expect(texto, isNot(contains('TOTAL')));
    });
  });

  group('servicios de impresión', () {
    late String bluetooth;
    late String wifi;
    late String web;

    setUpAll(() {
      String leer(String ruta) =>
          File(ruta).readAsStringSync().replaceAll('\r\n', '\n');
      bluetooth = leer('lib/services/bluetooth_printer_service.dart');
      wifi = leer('lib/services/wifi_printer_service.dart');
      web = leer('lib/services/web_printer_service_web.dart');
    });

    test('el recibo de caja lleva el mismo pie que la factura', () {
      expect(bluetooth, isNot(contains("if (title == 'FACTURA')")));
      expect(wifi, isNot(contains("if (title == 'FACTURA')")));
      expect(web, isNot(contains('final isFactura')));
    });

    test('las facturas usan la maquetación común', () {
      for (final fuente in [bluetooth, wifi]) {
        expect(fuente, contains('TicketLayout.productoBytes('));
        expect(fuente, contains('TicketLayout.totalBytes('));
        expect(fuente, isNot(contains("'TOTAL: \${ticketMoney(order.total)}'")));
        expect(fuente, isNot(contains(r"'  ${ticketMoney(item.precioUnitario)} = ")));
      }
    });

    test('la guía de almacén no imprime importes', () {
      for (final fuente in [bluetooth, wifi]) {
        expect(fuente, contains('TicketLayout.almacenProductoBytes('));
        expect(fuente, contains('TicketData.almacenResumen('));
        expect(fuente, isNot(contains(r'prod - \$')));
      }
      expect(web, isNot(contains('VALOR TOTAL')));
      expect(web, isNot(contains('class="price-line"')));
    });
  });
}

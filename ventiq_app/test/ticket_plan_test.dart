import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/utils/bt_chunks.dart';
import 'package:ventiq_app/utils/ticket_plan.dart';

void main() {
  List<String> claves(TicketPlan p) => [for (final t in p.secuencia) t.clave];

  group('TicketPlan: qué tickets imprime la tienda', () {
    test('solo factura: sin guía de almacén ni recibo de caja', () {
      final plan = TicketPlan.desdeConfig({
        'tickets_a_imprimir': ['cliente'],
      }, incluyeAlmacen: true);
      expect(claves(plan), ['cliente']);
      expect(plan.incluye(TicketTipo.almacen), isFalse);
      expect(plan.incluye(TicketTipo.caja), isFalse);
    });

    test('los tres, siempre en el mismo orden', () {
      final plan = TicketPlan.desdeConfig({
        'tickets_a_imprimir': ['caja', 'almacen', 'cliente'],
      }, incluyeAlmacen: true);
      expect(claves(plan), ['cliente', 'almacen', 'caja']);
    });

    test('lista vacía: no se imprime nada (lo que avisa el admin)', () {
      final plan = TicketPlan.desdeConfig({
        'tickets_a_imprimir': <String>[],
      }, incluyeAlmacen: true);
      expect(plan.vacio, isTrue);
    });

    test('sin configuración o con otro tipo: los tres, como siempre', () {
      for (final config in <Map<String, dynamic>?>[
        null,
        <String, dynamic>{},
        {'tickets_a_imprimir': null},
        {'tickets_a_imprimir': 'cliente'},
      ]) {
        expect(
          claves(TicketPlan.desdeConfig(config, incluyeAlmacen: true)),
          ['cliente', 'almacen', 'caja'],
        );
      }
    });

    test('la guía de almacén no sale en restaurante aunque la pida', () {
      final plan = TicketPlan.desdeConfig({
        'tickets_a_imprimir': ['cliente', 'almacen', 'caja'],
      }, incluyeAlmacen: false);
      expect(claves(plan), ['cliente', 'caja']);
    });

    test('ignora claves desconocidas (p. ej. cocina)', () {
      final plan = TicketPlan.desdeConfig({
        'tickets_a_imprimir': ['cocina', 'cliente'],
      }, incluyeAlmacen: true);
      expect(claves(plan), ['cliente']);
    });
  });

  group('los servicios de impresión respetan el plan', () {
    for (final archivo in [
      'lib/services/bluetooth_printer_service.dart',
      'lib/services/wifi_printer_service.dart',
      'lib/services/web_printer_service_web.dart',
    ]) {
      test('$archivo usa TicketPlan en printInvoice', () {
        final fuente = File(archivo).readAsStringSync();
        expect(fuente, contains('TicketPlan.cargar'));
        expect(fuente, contains('plan.secuencia'));
        // Ya no imprime los tres a ciegas.
        expect(fuente, isNot(contains("title: 'RECIBO VENDEDOR'")));
      });
    }

    test('la impresión por Sunmi también sigue la configuración', () {
      final fuente =
          File('lib/services/bluetooth_printer_service.dart').readAsStringSync();
      final sunmi = fuente.substring(
        fuente.indexOf('Future<void> printOrdersViaEscPos'),
        fuente.indexOf('Future<bool> printInvoice'),
      );
      expect(sunmi, contains('TicketPlan.cargar(order, config: storeConfig)'));
    });
  });

  group('trocearEnLineas: un trozo nunca termina a mitad de línea', () {
    List<int> texto(String s) => s.codeUnits;

    test('une todos los trozos y respeta el orden', () {
      final bytes = <int>[
        for (var i = 0; i < 40; i++) ...texto('linea numero $i\n'),
      ];
      final trozos = trocearEnLineas(bytes, maximo: 64);
      expect(trozos.expand((t) => t).toList(), bytes);
      for (final t in trozos) {
        expect(t.length, lessThanOrEqualTo(64));
      }
    });

    test('cada trozo termina en salto de línea', () {
      final bytes = <int>[
        for (var i = 0; i < 40; i++) ...texto('50x Diesel $i\n'),
      ];
      final trozos = trocearEnLineas(bytes, maximo: 50);
      for (final t in trozos) {
        expect(t.last, 0x0A);
      }
    });

    test('el caso real: «50x Diesel» queda entero en un solo trozo', () {
      // Relleno que deja el límite del trozo en medio de «50x Diesel».
      final relleno = '${'x' * 250}\n';
      final bytes = <int>[...texto(relleno), ...texto('50x Diesel\n')];
      final trozos = trocearEnLineas(bytes, maximo: 256);
      final alguno = trozos.any(
        (t) => String.fromCharCodes(t).contains('50x Diesel'),
      );
      expect(alguno, isTrue);
    });

    test('sin salto de línea corta en el máximo, como antes', () {
      final bytes = List<int>.filled(600, 0x41);
      final trozos = trocearEnLineas(bytes, maximo: 256);
      expect(trozos.map((t) => t.length), [256, 256, 88]);
    });

    test('vacío y menor que el máximo', () {
      expect(trocearEnLineas(const <int>[]), isEmpty);
      expect(trocearEnLineas(texto('abc\n')).single, texto('abc\n'));
    });
  });
}

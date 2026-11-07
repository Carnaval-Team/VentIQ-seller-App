import 'package:flutter_test/flutter_test.dart';

import 'package:ventiq_app/utils/ttl_cache.dart';

void main() {
  group('TtlCache', () {
    late DateTime ahora;

    TtlCache<String, int> crear() => TtlCache<String, int>(
      ttl: const Duration(seconds: 60),
      reloj: () => ahora,
    );

    setUp(() {
      ahora = DateTime(2026, 11, 2, 12, 0, 0);
    });

    test('devuelve el valor dentro del TTL', () {
      final TtlCache<String, int> cache = crear();
      cache.put('10800', 41000);

      ahora = ahora.add(const Duration(seconds: 59));

      expect(cache.get('10800'), 41000);
    });

    test('expira al llegar al TTL', () {
      final TtlCache<String, int> cache = crear();
      cache.put('10800', 41000);

      ahora = ahora.add(const Duration(seconds: 60));

      expect(cache.get('10800'), isNull);
      expect(cache.length, 0, reason: 'la entrada vencida se limpia');
    });

    test('removeWhere invalida por clave', () {
      final TtlCache<String, int> cache = crear();
      cache.put('10800|5', 1);
      cache.put('10800|0', 2);
      cache.put('10813|5', 3);

      cache.removeWhere((String clave, int _) => clave.startsWith('10800|'));

      expect(cache.length, 1);
      expect(cache.get('10813|5'), 3);
    });

    test('put reemplaza el valor y reinicia el reloj', () {
      final TtlCache<String, int> cache = crear();
      cache.put('a', 1);

      ahora = ahora.add(const Duration(seconds: 50));
      cache.put('a', 2);

      ahora = ahora.add(const Duration(seconds: 30));
      expect(cache.get('a'), 2, reason: 'el TTL cuenta desde el último put');
    });
  });
}

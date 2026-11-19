import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/utils/cadena_por_clave.dart';

void main() {
  test('dos aperturas del mismo TPV + vendedor no corren a la vez', () async {
    final cadena = CadenaPorClave();
    final eventos = <String>[];
    final liberarPrimera = Completer<void>();

    final primera = cadena.ejecutar('249:133', () async {
      eventos.add('inicio 1');
      await liberarPrimera.future;
      eventos.add('fin 1');
      return 3522;
    });
    final segunda = cadena.ejecutar('249:133', () async {
      eventos.add('inicio 2');
      return 3522;
    });

    await Future<void>.delayed(Duration.zero);
    expect(eventos, ['inicio 1']);

    liberarPrimera.complete();
    expect(await primera, 3522);
    expect(await segunda, 3522);
    expect(eventos, ['inicio 1', 'fin 1', 'inicio 2']);
    expect(cadena.vacia, isTrue);
  });

  test('claves distintas corren en paralelo', () async {
    final cadena = CadenaPorClave();
    final bloqueo = Completer<void>();
    var otraCorrio = false;

    final lenta = cadena.ejecutar('249:133', () => bloqueo.future);
    await cadena.ejecutar('249:297', () async => otraCorrio = true);

    expect(otraCorrio, isTrue);
    bloqueo.complete();
    await lenta;
  });

  test('si una falla, la siguiente de la misma clave igual corre', () async {
    final cadena = CadenaPorClave();

    final falla = cadena.ejecutar<int>('3:1', () async => throw StateError('x'));
    final sigue = cadena.ejecutar('3:1', () async => 13);

    await expectLater(falla, throwsStateError);
    expect(await sigue, 13);
  });
}

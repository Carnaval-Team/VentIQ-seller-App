import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/utils/fecha_rpc.dart';

void main() {
  test('la fecha de la cola sin offset sale como el mismo instante en UTC', () {
    // Así guarda la cola un cierre local (turno 13 de newa, 18/11).
    final local = DateTime(2026, 11, 18, 11, 7, 38, 5);
    final guardada = local.toIso8601String();
    expect(guardada.endsWith('Z'), isFalse);

    final enviada = fechaUtcParaRpc(guardada)!;

    expect(enviada.endsWith('Z'), isTrue);
    expect(DateTime.parse(enviada).isAtSameMomentAs(local), isTrue);
  });

  test('una fecha que ya trae zona conserva el instante', () {
    final enviada = fechaUtcParaRpc('2026-11-18T11:07:38.005-05:00')!;

    expect(enviada, '2026-11-18T16:07:38.005Z');
  });

  test('acepta DateTime y devuelve null sin fecha válida', () {
    final utc = DateTime.utc(2026, 11, 18, 16, 4, 5);

    expect(fechaUtcParaRpc(utc), '2026-11-18T16:04:05.000Z');
    expect(fechaUtcParaRpc(null), isNull);
    expect(fechaUtcParaRpc('no es fecha'), isNull);
  });
}

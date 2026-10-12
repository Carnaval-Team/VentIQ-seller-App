import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/sala_espera.dart';

/// El turno de la lista de espera llega por el RPC
/// `cliente_obtener_salas_espera` (`id_turno` + `turno`). Es importante que el
/// modelo lo tolere ausente: si la migración `38_sala_espera_turno.sql` todavía
/// no está aplicada, la app debe seguir funcionando y decir "cualquier turno" en
/// vez de reventar.
void main() {
  Map<String, dynamic> filaRpc({Object? idTurno, Object? turno}) => {
    'id': 12,
    'uuid_usuario': '00000000-0000-0000-0000-000000000001',
    'id_local_servicio': 7,
    'fecha_regla': '2026-04-02T00:00:00',
    'numero_cola': 5,
    'created_at': '2026-04-01T10:30:00',
    'ultimo_otorgado': 3,
    'personas_delante': 2,
    'es_su_turno': false,
    if (idTurno != null) 'id_turno': idTurno,
    if (turno != null) 'turno': turno,
    'servicio': {'id': 1, 'nombre': 'Transporte', 'foto': null},
    'local': {'id': 2, 'nombre': 'Carnaval', 'provincia': 'La Habana'},
  };

  test('lee el turno elegido cuando el RPC lo devuelve', () {
    final sala = SalaEspera.fromJson(filaRpc(idTurno: 9, turno: 'Mañana'));

    expect(sala.idTurno, 9);
    expect(sala.turnoNombre, 'Mañana');
    expect(sala.numeroCola, 5);
    expect(sala.personasDelante, 2);
  });

  test('sin las claves del turno no falla y queda como "cualquiera"', () {
    final sala = SalaEspera.fromJson(filaRpc());

    expect(sala.idTurno, isNull);
    expect(sala.turnoNombre, isNull);
  });

  test('un nombre de turno vacío se normaliza a null', () {
    final sala = SalaEspera.fromJson(filaRpc(idTurno: 4, turno: ''));

    expect(sala.idTurno, 4);
    expect(sala.turnoNombre, isNull);
  });

  test('acepta el turno como objeto (por si el RPC cambia a jsonb)', () {
    final sala = SalaEspera.fromJson(
      filaRpc(idTurno: 4, turno: {'id': 4, 'nombre': 'Tarde'}),
    );

    expect(sala.idTurno, 4);
    expect(sala.turnoNombre, 'Tarde');
  });

  test('formato PostgREST: el turno anidado no rompe el parseo', () {
    final sala = SalaEspera.fromJson({
      'id': 3,
      'uuid_usuario': '00000000-0000-0000-0000-000000000001',
      'id_local_servicio': 7,
      'fecha_regla': '2026-04-02T00:00:00',
      'numero_cola': 1,
      'created_at': '2026-04-01T10:30:00',
      'id_turno': 11,
      'local_servicio': {
        'id': 7,
        'id_local': 2,
        'id_servicio': 1,
        'servicio': {'id': 1, 'nombre': 'Transporte'},
        'local': {'id': 2, 'nombre': 'Carnaval'},
      },
    });

    expect(sala.localServicio, isNotNull);
    expect(sala.idTurno, 11);
    // El nombre del turno solo viene por el RPC; en PostgREST queda en null.
    expect(sala.turnoNombre, isNull);
  });
}

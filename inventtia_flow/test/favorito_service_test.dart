import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/providers/favoritos_provider.dart';
import 'package:inventtia_flow/services/favorito_service.dart';

/// `flow.favorito` tiene clave primaria compuesta
/// `(uuid_usuario, id_local_servicio)`. El servicio se apoya en ella para que
/// guardar dos veces sea idempotente, así que el parseo de esa fila y la
/// detección de "la tabla todavía no existe" son lo que conviene anclar.
void main() {
  group('Favorito.fromJson', () {
    test('lee una fila del formato de PostgREST', () {
      final favorito = Favorito.fromJson({
        'uuid_usuario': '11111111-2222-3333-4444-555555555555',
        'id_local_servicio': 12,
        'created_at': '2026-01-15T10:30:00',
      });
      expect(favorito.uuidUsuario, '11111111-2222-3333-4444-555555555555');
      expect(favorito.idLocalServicio, 12);
      expect(favorito.createdAt, DateTime(2026, 1, 15, 10, 30));
    });

    test('tolera created_at ausente o nulo', () {
      final sinFecha = Favorito.fromJson({
        'uuid_usuario': 'a',
        'id_local_servicio': 7,
      });
      expect(sinFecha.createdAt, isNull);
      expect(sinFecha.idLocalServicio, 7);

      final fechaNula = Favorito.fromJson({
        'uuid_usuario': 'a',
        'id_local_servicio': 7,
        'created_at': null,
      });
      expect(fechaNula.createdAt, isNull);
    });

    test('una fecha con formato inválido no lanza', () {
      final favorito = Favorito.fromJson({
        'uuid_usuario': 'a',
        'id_local_servicio': 7,
        'created_at': 'no-es-una-fecha',
      });
      expect(favorito.createdAt, isNull);
    });
  });

  group('esErrorDeTablaAusente', () {
    test('reconoce la tabla ausente (migración 25 sin aplicar)', () {
      expect(
        esErrorDeTablaAusente(
          Exception(
            "PostgrestException(message: Could not find the table "
            "'flow.favorito' in the schema cache, code: PGRST205)",
          ),
        ),
        isTrue,
      );
      expect(
        esErrorDeTablaAusente(
          Exception('relation "flow.favorito" does not exist (42P01)'),
        ),
        isTrue,
      );
    });

    test('NO confunde un fallo de red con una tabla ausente', () {
      // Si esto devolviera true, el corazón desaparecería por un corte de red
      // en vez de mostrarse con opción de reintentar.
      expect(
        esErrorDeTablaAusente(Exception('SocketException: Failed host lookup')),
        isFalse,
      );
      expect(
        esErrorDeTablaAusente(Exception('PostgrestException: JWT expired')),
        isFalse,
      );
      expect(
        esErrorDeTablaAusente(
          Exception('new row violates row-level security policy (42501)'),
        ),
        isFalse,
      );
    });
  });
}

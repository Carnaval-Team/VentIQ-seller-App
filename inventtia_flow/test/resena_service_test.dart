import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/resena_service.dart';

/// Contrato entre el JSON de `flow.resenas_de_servicio` / `resenas_recientes`
/// y los modelos Dart.
///
/// Estas pruebas fijan la forma exacta que devuelven los RPC del archivo
/// `26_resenas.sql`. Si alguien cambia una clave en el SQL y no en el modelo
/// (o al revés), aquí se ve.
void main() {
  group('ResumenResenas', () {
    test('lee total, promedio y distribución', () {
      final r = ResumenResenas.fromJson({
        'total': 12,
        'promedio': 4.3,
        'estrellas': {'5': 6, '4': 4, '3': 1, '2': 1, '1': 0},
      });
      expect(r.total, 12);
      expect(r.promedio, 4.3);
      expect(r.distribucion[5], 6);
      expect(r.distribucion[1], 0);
      expect(r.hayDatos, isTrue);
    });

    test('un servicio sin reseñas da total 0 y hayDatos false', () {
      // Es el caso de 5 de los 6 servicios del catálogo real.
      final r = ResumenResenas.fromJson({
        'total': 0,
        'promedio': 0,
        'estrellas': {'5': 0, '4': 0, '3': 0, '2': 0, '1': 0},
      });
      expect(r.total, 0);
      expect(r.hayDatos, isFalse);
    });

    test('null devuelve el resumen vacío sin lanzar', () {
      expect(ResumenResenas.fromJson(null).hayDatos, isFalse);
    });

    test('tolera que falte la distribución', () {
      final r = ResumenResenas.fromJson({'total': 3, 'promedio': 5.0});
      expect(r.hayDatos, isTrue);
      expect(r.distribucion.values.every((v) => v == 0), isTrue);
    });
  });

  group('Resena', () {
    test('lee una reseña del listado, con autor abreviado y es_mia', () {
      final r = Resena.fromJson({
        'id': 7,
        'puntuacion': 5,
        'comentario': 'Excelente atención',
        'created_at': '2026-03-01T10:00:00',
        'autor': 'Ana R.',
        'es_mia': true,
      });
      expect(r.id, 7);
      expect(r.puntuacion, 5);
      expect(r.autor, 'Ana R.');
      expect(r.esMia, isTrue);
      expect(r.tieneComentario, isTrue);
      expect(r.createdAt, DateTime(2026, 3, 1, 10));
    });

    test('sin comentario, tieneComentario es false', () {
      final r = Resena.fromJson({'id': 1, 'puntuacion': 4, 'comentario': null});
      expect(r.tieneComentario, isFalse);
    });

    test('un comentario de solo espacios no cuenta como comentario', () {
      final r = Resena.fromJson({
        'id': 1,
        'puntuacion': 4,
        'comentario': '   ',
      });
      expect(r.tieneComentario, isFalse);
    });

    test('sin autor usa "Cliente" como valor por defecto', () {
      // El RPC lo hace cuando el autor no tiene fila en `flow.perfil`. Con 5261
      // usuarios y 19 perfiles, es el caso habitual.
      final r = Resena.fromJson({'id': 1, 'puntuacion': 3});
      expect(r.autor, 'Cliente');
    });

    test('lee id_agenda, necesario para editar la propia reseña', () {
      final r = Resena.fromJson({'id': 9, 'puntuacion': 4, 'id_agenda': 42});
      expect(r.idAgenda, 42);
    });
  });

  group('ResenasDeServicio', () {
    test('parsea la respuesta completa del RPC', () {
      final data = ResenasDeServicio.fromJson({
        'ok': true,
        'resumen': {
          'total': 2,
          'promedio': 4.5,
          'estrellas': {'5': 1, '4': 1, '3': 0, '2': 0, '1': 0},
        },
        'items': [
          {
            'id': 1,
            'puntuacion': 5,
            'comentario': 'Muy bien',
            'autor': 'Luis P.',
          },
          {
            'id': 2,
            'puntuacion': 4,
            'comentario': 'Bien',
            'autor': 'Ana R.',
            'es_mia': true,
          },
        ],
        'mi_resena': {'id': 2, 'puntuacion': 4, 'id_agenda': 88},
        'agenda_resenable': null,
      });

      expect(data.resumen.total, 2);
      expect(data.items, hasLength(2));
      expect(data.miResena?.id, 2);
      expect(data.miResena?.idAgenda, 88);
      // Ya opinó y no tiene otra reserva completada: no debe ofrecerse el
      // formulario de nuevo.
      expect(data.puedoResenar, isFalse);
    });

    test('agenda_resenable habilita el formulario', () {
      final data = ResenasDeServicio.fromJson({
        'ok': true,
        'resumen': {'total': 0, 'promedio': 0, 'estrellas': {}},
        'items': <dynamic>[],
        'mi_resena': null,
        'agenda_resenable': {
          'id_agenda': 55,
          'atendido': '2026-02-10T09:30:00',
        },
      });
      expect(data.puedoResenar, isTrue);
      expect(data.agendaResenable?.idAgenda, 55);
      expect(data.agendaResenable?.atendido, DateTime(2026, 2, 10, 9, 30));
      expect(data.miResena, isNull);
    });

    test('ok:false se trata como vacío, no como éxito', () {
      // El RPC devuelve {ok:false} cuando no hay sesión válida. Tratarlo como
      // éxito pintaría una sección de reseñas falsa.
      final data = ResenasDeServicio.fromJson({
        'ok': false,
        'error': 'Sesion no valida',
      });
      expect(data.items, isEmpty);
      expect(data.resumen.hayDatos, isFalse);
      expect(data.puedoResenar, isFalse);
    });

    test('null (RPC inexistente) se trata como vacío', () {
      final data = ResenasDeServicio.fromJson(null);
      expect(data.items, isEmpty);
      expect(data.puedoResenar, isFalse);
    });
  });
}

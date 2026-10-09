import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/campana_service.dart';

/// Pruebas del modelo de campaña patrocinada.
///
/// `CampanaService.activas()` habla con Supabase, así que aquí se cubre el
/// parseo: es donde se cuelan los fallos de verdad (campos que faltan, `jsonb`
/// que llega con otro tipo, fechas nulas).
void main() {
  group('CampanaPatrocinada.fromJson', () {
    test('parsea una fila completa de campanas_activas()', () {
      final c = CampanaPatrocinada.fromJson({
        'id': 3,
        'titulo': 'Luna Studio',
        'subtitulo': 'Tu momento empieza aquí',
        'descripcion': 'Spa urbano',
        'id_local_servicio': 12,
        'id_entidad': null,
        'color_inicio': '#6D547D',
        'color_fin': '#C795B0',
        'icono': 'spa',
        'image_url': null,
        'prioridad': 5,
        'hasta': '2026-03-01T23:59:59.000Z',
        'local': 'Salon 1 Cejas',
        'servicio': 'Corte y peinado',
        'entidad': null,
      });

      expect(c.id, 3);
      expect(c.titulo, 'Luna Studio');
      expect(c.subtitulo, 'Tu momento empieza aquí');
      expect(c.idLocalServicio, 12);
      expect(c.idEntidad, isNull);
      expect(c.colorInicio, '#6D547D');
      expect(c.icono, 'spa');
      expect(c.prioridad, 5);
      expect(c.hasta, DateTime.utc(2026, 3, 1, 23, 59, 59));
      expect(c.local, 'Salon 1 Cejas');
      expect(c.servicio, 'Corte y peinado');
    });

    test('campos opcionales ausentes no rompen el parseo', () {
      final c = CampanaPatrocinada.fromJson({'id': 1, 'titulo': 'Básica'});

      expect(c.id, 1);
      expect(c.titulo, 'Básica');
      expect(c.subtitulo, isNull);
      expect(c.descripcion, isNull);
      expect(c.idLocalServicio, isNull);
      expect(c.idEntidad, isNull);
      expect(c.colorInicio, isNull);
      expect(c.colorFin, isNull);
      expect(c.icono, isNull);
      expect(c.imageUrl, isNull);
      expect(c.hasta, isNull);
      expect(c.local, isNull);
      expect(c.servicio, isNull);
      expect(c.entidad, isNull);
      // `prioridad` tiene valor por defecto: el servidor siempre la manda, pero
      // si faltara no debe quedar null.
      expect(c.prioridad, 0);
    });

    test('titulo ausente cae a cadena vacía en vez de lanzar', () {
      final c = CampanaPatrocinada.fromJson({'id': 9});
      expect(c.titulo, '');
    });

    test('hasta con valor no textual se ignora', () {
      expect(
        CampanaPatrocinada.fromJson({'id': 1, 'hasta': 12345}).hasta,
        isNull,
      );
      expect(
        CampanaPatrocinada.fromJson({'id': 1, 'hasta': 'no-es-fecha'}).hasta,
        isNull,
      );
    });

    test('id numérico en double (jsonb) se convierte a int', () {
      // PostgREST puede devolver números como double.
      final c = CampanaPatrocinada.fromJson({
        'id': 4.0,
        'prioridad': 2.0,
        'id_local_servicio': 19.0,
      });
      expect(c.id, 4);
      expect(c.prioridad, 2);
      expect(c.idLocalServicio, 19);
    });
  });

  group('CampanaPatrocinada — derivados', () {
    test('esDeServicio solo si hay id_local_servicio', () {
      expect(
        const CampanaPatrocinada(
          id: 1,
          titulo: 'A',
          idLocalServicio: 7,
        ).esDeServicio,
        isTrue,
      );
      expect(
        const CampanaPatrocinada(id: 2, titulo: 'B', idEntidad: 3).esDeServicio,
        isFalse,
      );
    });

    test('tieneImagen ignora cadenas vacías o en blanco', () {
      expect(
        const CampanaPatrocinada(
          id: 1,
          titulo: 'A',
          imageUrl: '  ',
        ).tieneImagen,
        isFalse,
      );
      expect(const CampanaPatrocinada(id: 1, titulo: 'A').tieneImagen, isFalse);
      expect(
        const CampanaPatrocinada(
          id: 1,
          titulo: 'A',
          imageUrl: 'https://x/y.jpg',
        ).tieneImagen,
        isTrue,
      );
    });

    test(
      'subtituloONombre prefiere el subtítulo y si no compone servicio·local',
      () {
        expect(
          const CampanaPatrocinada(
            id: 1,
            titulo: 'A',
            subtitulo: 'Promo de marzo',
            servicio: 'Corte',
            local: 'Salon 1',
          ).subtituloONombre,
          'Promo de marzo',
        );

        expect(
          const CampanaPatrocinada(
            id: 1,
            titulo: 'A',
            subtitulo: '   ',
            servicio: 'Corte',
            local: 'Salon 1',
          ).subtituloONombre,
          'Corte · Salon 1',
        );

        // Sin servicio ni local no debe quedar " · ".
        expect(
          const CampanaPatrocinada(id: 1, titulo: 'A').subtituloONombre,
          '',
        );
      },
    );

    test('subtituloONombre con solo uno de los dos no añade separador', () {
      expect(
        const CampanaPatrocinada(
          id: 1,
          titulo: 'A',
          local: 'Salon 1',
        ).subtituloONombre,
        'Salon 1',
      );
    });
  });
}

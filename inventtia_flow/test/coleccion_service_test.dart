import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/coleccion_service.dart';

/// Pruebas del modelo de colección temática.
///
/// `ColeccionService.activas()` habla con Supabase, así que aquí se cubre el
/// parseo de `colecciones_activas()`: es donde se cuelan los fallos de verdad
/// (`jsonb_agg` que llega con otro tipo, arrays vacíos, fechas nulas, números
/// como double).
void main() {
  group('Coleccion.fromJson', () {
    test('parsea una fila completa de colecciones_activas()', () {
      final c = Coleccion.fromJson({
        'id': 5,
        'titulo': 'Pack Novia',
        'subtitulo': 'Todo para el gran día',
        'icono': '💍',
        'color_inicio': '#8C5B72',
        'color_fin': '#C98CA4',
        'orden': 1,
        'hasta': '2026-03-01T23:59:59.000Z',
        'total_servicios': 3,
        'servicios': [12, 19, 7],
      });

      expect(c.id, 5);
      expect(c.titulo, 'Pack Novia');
      expect(c.subtitulo, 'Todo para el gran día');
      expect(c.icono, '💍');
      expect(c.colorInicio, '#8C5B72');
      expect(c.colorFin, '#C98CA4');
      expect(c.orden, 1);
      expect(c.hasta, DateTime.utc(2026, 3, 1, 23, 59, 59));
      expect(c.totalServicios, 3);
      expect(c.servicios, [12, 19, 7]);
      expect(c.tieneServicios, isTrue);
    });

    test('campos opcionales ausentes no rompen el parseo', () {
      final c = Coleccion.fromJson({'id': 1, 'titulo': 'Básica'});

      expect(c.id, 1);
      expect(c.titulo, 'Básica');
      expect(c.subtitulo, isNull);
      expect(c.icono, isNull);
      expect(c.colorInicio, isNull);
      expect(c.colorFin, isNull);
      expect(c.hasta, isNull);
      expect(c.orden, 0);
      expect(c.totalServicios, 0);
      expect(c.servicios, isEmpty);
      expect(c.tieneServicios, isFalse);
    });

    test('titulo ausente cae a cadena vacía en vez de lanzar', () {
      expect(Coleccion.fromJson({'id': 9}).titulo, '');
    });

    test('servicios ausente o con tipo que no es lista queda vacío', () {
      expect(Coleccion.fromJson({'id': 1}).servicios, isEmpty);
      expect(Coleccion.fromJson({'id': 1, 'servicios': null}).servicios, isEmpty);
      expect(Coleccion.fromJson({'id': 1, 'servicios': 'x'}).servicios, isEmpty);
      expect(Coleccion.fromJson({'id': 1, 'servicios': <String, dynamic>{}}).servicios, isEmpty);
    });

    test('elementos no numéricos del array se descartan', () {
      final c = Coleccion.fromJson({
        'id': 1,
        'servicios': [12, 'x', null, 19.0],
      });
      expect(c.servicios, [12, 19]);
    });

    test('hasta con valor no textual o inválido se ignora', () {
      expect(Coleccion.fromJson({'id': 1, 'hasta': 12345}).hasta, isNull);
      expect(Coleccion.fromJson({'id': 1, 'hasta': 'no-es-fecha'}).hasta, isNull);
      expect(Coleccion.fromJson({'id': 1, 'hasta': null}).hasta, isNull);
    });

    test('números en double (jsonb) se convierten a int', () {
      final c = Coleccion.fromJson({
        'id': 4.0,
        'orden': 2.0,
        'total_servicios': 3.0,
        'servicios': [7.0, 8.0],
      });
      expect(c.id, 4);
      expect(c.orden, 2);
      expect(c.totalServicios, 3);
      expect(c.servicios, [7, 8]);
    });
  });

  group('Coleccion — derivados', () {
    test('etiquetaServicios concuerda en número', () {
      expect(
        const Coleccion(id: 1, titulo: 'A', totalServicios: 1).etiquetaServicios,
        '1 servicio',
      );
      // Una colección sin servicios no llega al cliente, pero el texto no debe
      // quedar en "1 servicio" si algún día llegara.
      expect(
        const Coleccion(id: 1, titulo: 'A', totalServicios: 0).etiquetaServicios,
        '0 servicios',
      );
      expect(
        const Coleccion(id: 1, titulo: 'A', totalServicios: 12).etiquetaServicios,
        '12 servicios',
      );
    });

    test('subtituloORecuento prefiere el subtítulo real', () {
      expect(
        const Coleccion(
          id: 1,
          titulo: 'A',
          subtitulo: 'Todo para el gran día',
          totalServicios: 3,
        ).subtituloORecuento,
        'Todo para el gran día',
      );
    });

    test('subtituloORecuento cae al recuento si falta o está en blanco', () {
      expect(
        const Coleccion(
          id: 1,
          titulo: 'A',
          subtitulo: '   ',
          totalServicios: 3,
        ).subtituloORecuento,
        '3 servicios',
      );
      expect(
        const Coleccion(id: 1, titulo: 'A', totalServicios: 3)
            .subtituloORecuento,
        '3 servicios',
      );
    });

    test('tieneServicios solo con al menos un id', () {
      expect(const Coleccion(id: 1, titulo: 'A').tieneServicios, isFalse);
      expect(
        const Coleccion(id: 1, titulo: 'A', servicios: [1]).tieneServicios,
        isTrue,
      );
    });
  });
}

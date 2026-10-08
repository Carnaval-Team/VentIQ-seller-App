import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/tipo_actividad_service.dart';

/// El código es la clave estable que viaja al cliente dentro de
/// `cliente_obtener_servicios` y la que valida `admin_guardar_tipo_actividad`,
/// así que la propuesta automática y la validación deben coincidir.
void main() {
  group('codigoDesdeNombre', () {
    test('pasa a minúsculas y separa con guion bajo', () {
      expect(
        TipoActividad.codigoDesdeNombre('Cejas y Pestañas'),
        'cejas_y_pestanas',
      );
      expect(
        TipoActividad.codigoDesdeNombre('Hogar y Reparaciones'),
        'hogar_y_reparaciones',
      );
    });

    test('quita acentos y eñes', () {
      expect(TipoActividad.codigoDesdeNombre('Uñas'), 'unas');
      expect(TipoActividad.codigoDesdeNombre('Peluquería'), 'peluqueria');
      expect(
        TipoActividad.codigoDesdeNombre('Estética y Spa'),
        'estetica_y_spa',
      );
    });

    test('no deja guiones bajos al principio ni al final', () {
      expect(TipoActividad.codigoDesdeNombre('  Salud  '), 'salud');
      expect(TipoActividad.codigoDesdeNombre('¡Eventos!'), 'eventos');
    });

    test('colapsa signos repetidos en un solo guion bajo', () {
      expect(TipoActividad.codigoDesdeNombre('A -- B'), 'a_b');
      expect(TipoActividad.codigoDesdeNombre('A / B'), 'a_b');
    });

    test('replica la cadena de normalización del SQL', () {
      // `admin_guardar_tipo_actividad` hace:
      //   lower → translate(acentos) → regexp_replace('[^a-z0-9]+','_','g')
      //   → trim(both '_' from …)
      // Si las dos normalizaciones divergen, el usuario ve un código y se
      // guarda otro distinto.
      expect(
        TipoActividad.codigoDesdeNombre('  Cejas & Pestañas!!!  '),
        'cejas_pestanas',
      );
      expect(TipoActividad.codigoDesdeNombre('__ya_limpio__'), 'ya_limpio');
      expect(TipoActividad.codigoDesdeNombre('A.B/C'), 'a_b_c');
    });

    test('el resultado siempre supera la validación del RPC', () {
      for (final nombre in [
        'Cejas y Pestañas',
        'Uñas',
        'Peluquería y Barbería',
        'Estética y Spa',
        'Transporte en ómnibus',
        'Tecnología',
      ]) {
        final codigo = TipoActividad.codigoDesdeNombre(nombre);
        expect(
          TipoActividad.codigoValido(codigo),
          isTrue,
          reason: '«$nombre» generó «$codigo»',
        );
      }
    });
  });

  group('codigoValido', () {
    test('acepta el formato del RPC', () {
      expect(TipoActividad.codigoValido('unas'), isTrue);
      expect(TipoActividad.codigoValido('transporte_omnibus'), isTrue);
      expect(TipoActividad.codigoValido('a1b2c3'), isTrue);
    });

    test('rechaza lo que el RPC rechazaría', () {
      expect(TipoActividad.codigoValido('ab'), isFalse); // < 3 caracteres
      expect(TipoActividad.codigoValido('Uñas'), isFalse); // mayúscula/acento
      expect(TipoActividad.codigoValido('con espacio'), isFalse);
      expect(TipoActividad.codigoValido('con-guion'), isFalse);
      expect(TipoActividad.codigoValido(''), isFalse);
      expect(TipoActividad.codigoValido('a' * 65), isFalse); // > 64 caracteres
    });
  });

  group('fromJson', () {
    test('lee las filas del nomenclador', () {
      final tipo = TipoActividad.fromJson({
        'id': 4,
        'codigo': 'cejas_pestanas',
        'nombre': 'Cejas y Pestañas',
        'activo': true,
      });
      expect(tipo.id, 4);
      expect(tipo.codigo, 'cejas_pestanas');
      expect(tipo.nombre, 'Cejas y Pestañas');
      expect(tipo.activo, isTrue);
    });

    test('tolera columnas ausentes sin lanzar', () {
      final tipo = TipoActividad.fromJson({'id': 1});
      expect(tipo.codigo, '');
      expect(tipo.nombre, '');
      expect(tipo.activo, isTrue);
    });
  });
}

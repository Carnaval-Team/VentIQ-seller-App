import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/recurso.dart';
import 'package:inventtia_flow/models/servicio.dart';

/// Publicación de locales, servicios y pares local-servicio
/// (puntos 3, 4 y 8 del plan de mejoras).
///
/// La regla de oro es `LocalServicio.activoEfectivo`: un par se ve si y solo si
/// están activos el par, el local **y** el servicio. Es la réplica Dart de
/// `flow._ls_disponible` y la usan el filtro defensivo del cliente y los chips
/// del admin, así que conviene fijarla con pruebas.
void main() {
  Servicio servicio({bool activo = true}) => Servicio(
    id: 1,
    nombre: 'Corte de uñas',
    createdAt: DateTime(2025),
    activo: activo,
  );

  Local local({bool activo = true}) => Local(
    id: 1,
    nombre: 'Local Centro',
    createdAt: DateTime(2025),
    activo: activo,
  );

  LocalServicio ls({
    bool activo = true,
    bool localActivo = true,
    bool servicioActivo = true,
    bool soloTurnos = false,
    bool sinTramos = false,
    bool conLocal = true,
    bool conServicio = true,
  }) => LocalServicio(
    id: 10,
    idLocal: 1,
    idServicio: 1,
    local: conLocal ? local(activo: localActivo) : null,
    servicio: conServicio ? servicio(activo: servicioActivo) : null,
    createdAt: DateTime(2025),
    activo: activo,
    soloTurnos: soloTurnos,
    sinTramos: sinTramos,
  );

  group('LocalServicio.activoEfectivo', () {
    test('visible solo si los tres están activos', () {
      expect(ls().activoEfectivo, isTrue);
    });

    test('el par inactivo lo oculta', () {
      expect(ls(activo: false).activoEfectivo, isFalse);
    });

    test('el local inactivo oculta TODOS sus servicios', () {
      expect(ls(localActivo: false).activoEfectivo, isFalse);
    });

    test('el servicio inactivo lo oculta en todos los locales', () {
      expect(ls(servicioActivo: false).activoEfectivo, isFalse);
    });

    test('sin joins no oculta de más: manda solo `activo`', () {
      // Un payload PostgREST sin `app_dat_locales`/`app_dat_servicios` no puede
      // demostrar que el local esté inactivo, así que no se esconde el ítem.
      expect(ls(conLocal: false, conServicio: false).activoEfectivo, isTrue);
      expect(
        ls(conLocal: false, conServicio: false, activo: false).activoEfectivo,
        isFalse,
      );
    });
  });

  group('valores por defecto del parseo', () {
    test('sin la columna `activo` se asume publicado', () {
      // Migración 40 sin aplicar (o respuesta cacheada): nunca ocultar por
      // accidente todo el catálogo.
      final s = Servicio.fromJson({
        'id': 3,
        'nombre': 'Corte',
        'created_at': '2025-01-01T00:00:00Z',
      });
      expect(s.activo, isTrue);

      final l = Local.fromJson({
        'id': 4,
        'nombre': 'Centro',
        'created_at': '2025-01-01T00:00:00Z',
      });
      expect(l.activo, isTrue);
    });

    test('lee `activo` en falso del payload', () {
      final s = Servicio.fromJson({
        'id': 3,
        'nombre': 'Corte',
        'created_at': '2025-01-01T00:00:00Z',
        'activo': false,
      });
      expect(s.activo, isFalse);
    });

    test('lee el horario estructurado del local', () {
      final l = Local.fromJson({
        'id': 4,
        'nombre': 'Centro',
        'created_at': '2025-01-01T00:00:00Z',
        'horario_atencion': 'Lun, Mié, Vie 9:00-17:00',
        'horario_detalle': {
          'dias': [1, 3, 5],
          'apertura': '09:00',
          'cierre': '17:00',
        },
      });
      expect(l.horarioDetalle, isNotNull);
      expect(l.horarioDetalle!['dias'], [1, 3, 5]);
    });
  });

  group('modos simplificados', () {
    test('ocultaTramos con cualquiera de los dos modos', () {
      expect(ls().ocultaTramos, isFalse);
      expect(ls(sinTramos: true).ocultaTramos, isTrue);
      expect(ls(soloTurnos: true).ocultaTramos, isTrue);
    });

    test('`solo_turnos` implica que tampoco se muestran los recursos', () {
      final conAmbos = ls(soloTurnos: true, sinTramos: true);
      expect(conAmbos.soloTurnos, isTrue);
      expect(conAmbos.ocultaTramos, isTrue);
    });

    test('copyWith respeta los modos y los activos', () {
      final base = ls();
      final apagado = base.copyWith(activo: false, sinTramos: true);
      expect(apagado.activo, isFalse);
      expect(apagado.sinTramos, isTrue);
      // No se pierde el resto.
      expect(apagado.local?.nombre, 'Local Centro');
      expect(apagado.id, base.id);
    });
  });

  group('Recurso.esCupoInterno', () {
    test('reconoce el recurso oculto que crea la migración 41', () {
      final r = Recurso(id: 1, nombre: 'Cupo', capacidad: 3);
      expect(r.esCupoInterno, isTrue);
      // La comparación no depende de mayúsculas ni espacios sobrantes.
      expect(Recurso(id: 1, nombre: '  cupo ').esCupoInterno, isTrue);
    });

    test('un recurso real no se confunde con el cupo interno', () {
      expect(Recurso(id: 2, nombre: 'Mesa 3').esCupoInterno, isFalse);
      expect(Recurso(id: 3, nombre: 'Cupo grande').esCupoInterno, isFalse);
    });
  });
}

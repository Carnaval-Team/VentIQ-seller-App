import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/resena_service.dart';

/// [ResenaPendiente] es lo que viaja del RPC `cliente_resenas_pendientes`
/// (migración 59) al cartel. Aquí se fija el contrato del JSON y la etiqueta de
/// fecha, que es lo único que el cartel pone encima de la foto.
void main() {
  Map<String, dynamic> fila({
    int idAgenda = 41,
    int idLocalServicio = 7,
    String? servicio = 'Corte de cabello',
    String? local = 'Salón Bella',
    String? foto,
    String? categoria,
    String? atendido = '2026-10-22T15:30:00',
  }) => <String, dynamic>{
    'id_agenda': idAgenda,
    'id_local_servicio': idLocalServicio,
    'servicio': servicio,
    'local': local,
    'servicio_foto': foto,
    'categoria': categoria,
    'atendido': atendido,
  };

  group('ResenaPendiente.fromJson', () {
    test('lee todas las claves del RPC', () {
      final p = ResenaPendiente.fromJson(
        fila(
          foto: 'https://x/servicios/14.jpg',
          categoria: 'Cejas y Pestañas',
        ),
      );
      expect(p.idAgenda, 41);
      expect(p.idLocalServicio, 7);
      expect(p.servicioNombre, 'Corte de cabello');
      expect(p.localNombre, 'Salón Bella');
      expect(p.servicioFoto, 'https://x/servicios/14.jpg');
      expect(p.categoria, 'Cejas y Pestañas');
      expect(p.atendido, DateTime(2026, 10, 22, 15, 30));
    });

    test('un servicio sin nombre cae en un genérico, no en texto vacío', () {
      // El RPC puede devolver NULL si el nomenclador se editó por debajo.
      final p = ResenaPendiente.fromJson(fila(servicio: null));
      expect(p.servicioNombre, 'el servicio');
    });

    test('tolera foto, local, categoría y fecha nulos', () {
      final p = ResenaPendiente.fromJson(
        fila(local: null, foto: null, categoria: null, atendido: null),
      );
      expect(p.localNombre, '');
      expect(p.servicioFoto, isNull);
      expect(p.categoria, isNull);
      expect(p.atendido, isNull);
      // Sin fecha no se pinta fecha: la cadena vacía la descarta el `join`.
      expect(p.etiquetaFecha(), '');
    });

    test('recorta espacios del nombre del servicio', () {
      final p = ResenaPendiente.fromJson(fila(servicio: '  Lifting De Cejas  '));
      expect(p.servicioNombre, 'Lifting De Cejas');
    });
  });

  group('etiquetaFecha', () {
    // Todas las pruebas fijan "ahora" para no depender del reloj de la máquina.
    final ahora = DateTime(2026, 10, 24, 12, 0);

    ResenaPendiente conFecha(DateTime? fecha) => ResenaPendiente(
      idAgenda: 1,
      idLocalServicio: 1,
      servicioNombre: 'Corte',
      localNombre: 'Salón',
      atendido: fecha,
    );

    test('mismo día ⇒ hoy, aunque hayan pasado horas', () {
      expect(
        conFecha(DateTime(2026, 10, 24, 8, 0)).etiquetaFecha(ahora: ahora),
        'hoy',
      );
    });

    test('día anterior ⇒ ayer', () {
      expect(
        conFecha(DateTime(2026, 10, 23, 23, 59)).etiquetaFecha(ahora: ahora),
        'ayer',
      );
    });

    test('de 2 a 6 días ⇒ hace N días', () {
      expect(
        conFecha(DateTime(2026, 10, 22, 15, 30)).etiquetaFecha(ahora: ahora),
        'hace 2 días',
      );
      expect(
        conFecha(DateTime(2026, 10, 18, 9, 0)).etiquetaFecha(ahora: ahora),
        'hace 6 días',
      );
    });

    test('más de una semana ⇒ fecha corta', () {
      expect(
        conFecha(DateTime(2026, 10, 14, 14, 52)).etiquetaFecha(ahora: ahora),
        'el 14/10/2026',
      );
    });

    test('una fecha futura no dice "hace -N días"', () {
      // No debería pasar (solo se pide de reservas completadas), pero si el
      // reloj del móvil va atrasado no puede salir un texto absurdo.
      expect(
        conFecha(DateTime(2026, 10, 26, 10, 0)).etiquetaFecha(ahora: ahora),
        'el 26/10/2026',
      );
    });

    test('sin fecha no hay etiqueta', () {
      expect(conFecha(null).etiquetaFecha(ahora: ahora), '');
    });
  });
}

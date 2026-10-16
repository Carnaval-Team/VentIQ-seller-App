import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/campo_adicional.dart';
import 'package:inventtia_flow/models/config_precio.dart';
import 'package:inventtia_flow/models/disponibilidad_dia.dart';
import 'package:inventtia_flow/models/servicio.dart';
import 'package:inventtia_flow/screens/reserva_multiple_screen.dart'
    show mensajeDeErrorDeReserva;
import 'package:inventtia_flow/services/home_catalog_service.dart';
import 'package:inventtia_flow/utils/coleccion_servicios.dart';

/// Pruebas de las reglas de armado de una colección.
///
/// Todo lo que se cubre aquí decide **qué se puede reservar y por cuánto** en la
/// vista de la colección y en el asistente de reserva múltiple, y no toca la
/// red: agrupar establecimientos, el rango de precios, la suma de la selección,
/// los días reservables, el cupo por turno y las etiquetas de fecha. Son justo
/// las piezas que se rompen en silencio.
HomeCatalogItem _item({
  required int id,
  String titulo = 'Servicio',
  String local = 'Local',
  double? precio,
  String? moneda,
  int cantidadMax = 1,
  bool permiteDirecta = true,
  Servicio? servicio,
  String? provincia,
}) {
  return HomeCatalogItem(
    id: id,
    title: titulo,
    venue: local,
    category: HomeCatalogCategory.todas,
    price: precio,
    currency: moneda,
    provincia: provincia,
    permiteReservaDirecta: permiteDirecta,
    cantidadMaxCapacidad: cantidadMax,
    localServicio: LocalServicio(
      id: id,
      idLocal: 1,
      idServicio: id,
      createdAt: DateTime(2026),
      permiteReservaDirecta: permiteDirecta,
      cantidadMaxCapacidad: cantidadMax,
      servicio: servicio,
    ),
  );
}

Servicio _servicio({
  bool permiteTercero = false,
  List<CampoAdicional> campos = const [],
  ConfigPrecio? config,
}) {
  return Servicio(
    id: 1,
    nombre: 'Servicio',
    createdAt: DateTime(2026),
    permiteTercero: permiteTercero,
    camposAdicionales: campos,
    configPrecio: config,
  );
}

DisponibilidadDia _dia(
  DateTime fecha, {
  int disponibles = 3,
  List<TurnoDisponible> turnos = const [],
}) {
  return DisponibilidadDia(
    fecha: fecha,
    cantidad: 10,
    agendados: 10 - disponibles,
    disponibles: disponibles,
    turnos: turnos,
  );
}

TurnoDisponible _turno({
  int idTurno = 1,
  String nombre = 'Mañana',
  int disponibles = 2,
  String? horaInicio,
  String? horaFin,
}) {
  return TurnoDisponible(
    idRecurso: 1,
    recurso: 'Sala',
    idTurno: idTurno,
    turno: nombre,
    disponibles: disponibles,
    horaInicio: horaInicio,
    horaFin: horaFin,
  );
}

void main() {
  group('agruparPorEstablecimiento', () {
    test('agrupa por local conservando el orden de la curaduría', () {
      final grupos = agruparPorEstablecimiento([
        _item(id: 1, local: 'Spa A', titulo: 'Facial'),
        _item(id: 2, local: 'Studio B', titulo: 'Corte'),
        _item(id: 3, local: 'Spa A', titulo: 'Masaje'),
      ]);

      expect(grupos.map((g) => g.nombre), ['Spa A', 'Studio B']);
      expect(grupos.first.servicios.map((i) => i.title), ['Facial', 'Masaje']);
      expect(grupos.first.total, 2);
      expect(grupos.last.total, 1);
    });

    test('usa la ubicación del primer servicio del grupo', () {
      final grupos = agruparPorEstablecimiento([
        _item(id: 1, local: 'Spa A', provincia: 'Villa Clara'),
        _item(id: 2, local: 'Spa A'),
      ]);

      expect(grupos.single.ubicacion, 'Villa Clara');
    });

    test('un local sin nombre no descuadra el agrupado', () {
      final grupos = agruparPorEstablecimiento([
        _item(id: 1, local: '   '),
        _item(id: 2, local: 'Spa A'),
      ]);

      expect(grupos.map((g) => g.nombre), ['Establecimiento', 'Spa A']);
    });

    test('lista vacía devuelve lista vacía', () {
      expect(agruparPorEstablecimiento(const []), isEmpty);
    });
  });

  group('rangoPrecios', () {
    test('sin precios devuelve null en vez de 0', () {
      expect(rangoPrecios([_item(id: 1), _item(id: 2)]), isNull);
    });

    test('calcula mínimo y máximo en una sola moneda', () {
      final rango = rangoPrecios([
        _item(id: 1, precio: 25, moneda: 'USD'),
        _item(id: 2, precio: 10, moneda: 'USD'),
        _item(id: 3, precio: 18, moneda: 'USD'),
      ]);

      expect(rango, isNotNull);
      expect(rango!.minimo, 10);
      expect(rango.maximo, 25);
      expect(rango.moneda, 'USD');
      expect(rango.mixta, isFalse);
      expect(rango.unico, isFalse);
    });

    test('un solo precio es un rango de un punto', () {
      final rango = rangoPrecios([_item(id: 1, precio: 12, moneda: 'CUP')]);

      expect(rango!.minimo, 12);
      expect(rango.maximo, 12);
      expect(rango.unico, isTrue);
    });

    test('con monedas mezcladas describe la mayoritaria y lo avisa', () {
      final rango = rangoPrecios([
        _item(id: 1, precio: 20, moneda: 'CUP'),
        _item(id: 2, precio: 30, moneda: 'CUP'),
        _item(id: 3, precio: 5, moneda: 'USD'),
      ]);

      expect(rango!.moneda, 'CUP');
      expect(rango.minimo, 20);
      expect(rango.maximo, 30);
      expect(rango.mixta, isTrue);
    });

    test('precios en cero o negativos no cuentan como precio', () {
      expect(rangoPrecios([_item(id: 1, precio: 0, moneda: 'USD')]), isNull);
    });

    test('sin moneda no se puede afirmar un importe', () {
      expect(rangoPrecios([_item(id: 1, precio: 20)]), isNull);
    });
  });

  group('resumirSeleccion', () {
    test('sin selección no hay nada que resumir', () {
      final r = resumirSeleccion(const []);

      expect(r.haySeleccion, isFalse);
      expect(r.servicios, 0);
      expect(r.estimado, isNull);
      expect(r.etiquetaServicios, '0 servicios');
    });

    test('cuenta servicios y establecimientos distintos', () {
      final r = resumirSeleccion([
        _item(id: 1, local: 'Spa A', precio: 10, moneda: 'USD'),
        _item(id: 2, local: 'Spa A', precio: 15, moneda: 'USD'),
        _item(id: 3, local: 'Studio B', precio: 30, moneda: 'USD'),
      ]);

      expect(r.servicios, 3);
      expect(r.establecimientos, 2);
      expect(r.etiquetaServicios, '3 servicios');
      expect(r.etiquetaEstablecimientos, '2 establecimientos');
      expect(r.estimado, 55);
      expect(r.sumaCompleta, isTrue);
    });

    test('un servicio se dice en singular', () {
      final r = resumirSeleccion([_item(id: 1, local: 'Spa A')]);

      expect(r.etiquetaServicios, '1 servicio');
      expect(r.etiquetaEstablecimientos, '1 establecimiento');
    });

    test('si falta un precio no se enseña un total incompleto', () {
      final r = resumirSeleccion([
        _item(id: 1, local: 'Spa A', precio: 10, moneda: 'USD'),
        _item(id: 2, local: 'Spa A'),
      ]);

      expect(r.servicios, 2);
      expect(r.estimado, isNull);
      expect(r.sumaCompleta, isFalse);
    });

    test('monedas distintas no se suman entre sí', () {
      final r = resumirSeleccion([
        _item(id: 1, local: 'Spa A', precio: 10, moneda: 'USD'),
        _item(id: 2, local: 'Spa A', precio: 900, moneda: 'CUP'),
      ]);

      expect(r.estimado, isNull);
      expect(r.moneda, isNull);
      expect(r.sumaCompleta, isFalse);
    });
  });

  group('elegibilidad para reservar en lote', () {
    test('reserva directa normal sí entra', () {
      final item = _item(id: 1);

      expect(reservableEnLote(item), isTrue);
      expect(motivoNoReservableEnLote(item), isNull);
    });

    test('sin reserva directa se queda en lista de espera', () {
      final item = _item(id: 1, permiteDirecta: false);

      expect(reservableEnLote(item), isFalse);
      expect(motivoNoReservableEnLote(item), 'Solo lista de espera');
      expect(soloListaDeEspera(item), isTrue);
    });

    test('transporte ómnibus se reserva en su propia ficha', () {
      final item = _item(
        id: 1,
        permiteDirecta: true,
        servicio: Servicio(
          id: 1,
          nombre: 'Ómnibus',
          createdAt: DateTime(2026),
          tipoActividad: 'transporte_omnibus',
        ),
      );

      expect(item.localServicio!.esTransporteOmnibus, isTrue);
      expect(reservableEnLote(item), isFalse);
      expect(motivoNoReservableEnLote(item), 'Se reserva en su ficha');
    });
  });

  group('requiereOpciones', () {
    test('un servicio pelado no pide nada', () {
      expect(requiereOpciones(_item(id: 1, servicio: _servicio())), isFalse);
    });

    test('con campos adicionales exige pasar por la hoja', () {
      final item = _item(
        id: 1,
        servicio: _servicio(
          campos: [CampoAdicional(clave: 'largo', etiqueta: 'Largo')],
        ),
      );

      expect(requiereOpciones(item), isTrue);
    });

    test('permite terceros exige pasar por la hoja', () {
      expect(
        requiereOpciones(
          _item(id: 1, servicio: _servicio(permiteTercero: true)),
        ),
        isTrue,
      );
    });

    test('con precio configurado hay que elegir moneda', () {
      final item = _item(
        id: 1,
        servicio: _servicio(
          config: ConfigPrecio(preciosBase: const {'USD': 20}),
        ),
      );

      expect(requiereOpciones(item), isTrue);
    });

    test('sin servicio no se puede exigir nada', () {
      expect(requiereOpciones(_item(id: 1)), isFalse);
    });
  });

  group('precioCotizable', () {
    test('precio base configurado sí se cotiza', () {
      final item = _item(
        id: 1,
        servicio: _servicio(
          config: ConfigPrecio(preciosBase: const {'USD': 20}),
        ),
      );

      expect(precioCotizable(item), isTrue);
    });

    test('config_precio vacío no se cotiza (nada de "0 USD")', () {
      expect(precioCotizable(_item(id: 1, servicio: _servicio())), isFalse);
      expect(precioCotizable(_item(id: 1)), isFalse);
    });
  });

  group('diasReservables', () {
    test('descarta los días sin cupo y ordena por fecha', () {
      final dias = diasReservables([
        _dia(DateTime(2026, 3, 5), disponibles: 0),
        _dia(DateTime(2026, 3, 3)),
        _dia(DateTime(2026, 3, 4), disponibles: 1),
      ]);

      expect(dias.map((d) => d.fecha.day), [3, 4]);
    });

    test('sin días con cupo devuelve lista vacía', () {
      expect(
        diasReservables([_dia(DateTime(2026, 3, 5), disponibles: 0)]),
        isEmpty,
      );
    });
  });

  group('cupo y máximo reservable', () {
    test('sin turno manda el cupo del día', () {
      final dia = _dia(DateTime(2026, 3, 3), disponibles: 4);

      expect(cupoDe(dia: dia), 4);
    });

    test('con turno manda el cupo del turno', () {
      final dia = _dia(DateTime(2026, 3, 3), disponibles: 4);
      final turno = _turno(disponibles: 2);

      expect(cupoDe(dia: dia, turno: turno), 2);
    });

    test('el máximo es el menor entre el tope del admin y el cupo', () {
      final dia = _dia(DateTime(2026, 3, 3), disponibles: 5);

      expect(
        maxCantidadReservable(item: _item(id: 1, cantidadMax: 3), dia: dia),
        3,
      );
      expect(
        maxCantidadReservable(item: _item(id: 1, cantidadMax: 9), dia: dia),
        5,
      );
    });

    test('un cupo desconocido (0) no deja el asistente sin reservar', () {
      final dia = _dia(DateTime(2026, 3, 3), disponibles: 0);
      final turno = _turno(disponibles: 0);

      expect(
        maxCantidadReservable(item: _item(id: 1, cantidadMax: 2), dia: dia),
        1,
      );
      expect(
        maxCantidadReservable(
          item: _item(id: 1, cantidadMax: 2),
          dia: dia,
          turno: turno,
        ),
        1,
      );
    });
  });

  group('etiquetas', () {
    final ahora = DateTime(2026, 3, 3, 10);

    test('hoy y mañana se dicen por su nombre', () {
      expect(etiquetaDiaCorto(DateTime(2026, 3, 3, 22), ahora), 'Hoy');
      expect(etiquetaDiaCorto(DateTime(2026, 3, 4), ahora), 'Mañana');
    });

    test('más lejos usa el día de la semana y el número', () {
      // 2026-03-07 es sábado.
      expect(etiquetaDiaCorto(DateTime(2026, 3, 7), ahora), 'Sáb 7');
    });

    test('el día largo añade la fecha solo cuando es relativo', () {
      expect(etiquetaDiaLargo(DateTime(2026, 3, 3), ahora), 'Hoy, 3 mar');
      expect(etiquetaDiaLargo(DateTime(2026, 3, 7), ahora), 'Sáb 7 · sábado');
    });

    test('fecha corta en español, sin intl', () {
      expect(fechaCorta(DateTime(2026, 3, 9)), '9 mar');
      expect(fechaCorta(DateTime(2026, 12, 31)), '31 dic');
    });

    test('el turno se enseña con su hora cuando la tiene', () {
      expect(etiquetaTurno(_turno(nombre: 'Mañana')), 'Mañana');

      final conHora = _turno(
        nombre: 'Mañana',
        horaInicio: '09:00',
        horaFin: '11:00',
      );
      expect(etiquetaTurno(conHora), 'Mañana · 09:00 – 11:00');
    });

    test('un turno sin nombre no queda en blanco', () {
      expect(etiquetaTurno(_turno(nombre: '  ')), 'Turno');
    });

    test('importeCorto no inventa decimales ni moneda', () {
      expect(importeCorto(18, 'USD'), '18 USD');
      expect(importeCorto(18.5, 'USD'), '18.50 USD');
      expect(importeCorto(10, null), '10 USD');
    });
  });

  group('mensajeDeErrorDeReserva', () {
    test('quita el prefijo Exception para leer el mensaje del servidor', () {
      expect(
        mensajeDeErrorDeReserva(Exception('Ya tienes una reserva ese dia')),
        'Ya tienes una reserva ese dia',
      );
    });

    test('un error sin texto no deja el hueco vacío', () {
      expect(mensajeDeErrorDeReserva(Exception('')), isNotEmpty);
    });
  });
}

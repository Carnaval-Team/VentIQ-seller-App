import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:inventtia_flow/models/resumen_reservas.dart';

/// Payload de ejemplo, copiado del contrato §1.1 del plan
/// (`flow.admin_calendario_reservas`).
Map<String, dynamic> payloadCompleto() => <String, dynamic>{
  'ok': true,
  'rango': <String, dynamic>{
    'hoy': '2026-10-27',
    'desde': '2026-10-27',
    'hasta': '2027-03-31',
    'ultimo_dia_con_reserva': '2027-03-14',
    'truncado': false,
  },
  'resumen': <String, dynamic>{
    'total': 12,
    'reservadas': 6,
    'canceladas': 2,
    'completadas': 4,
    'por_servicio': <dynamic>[
      <String, dynamic>{'servicio': 'Corte', 'total': 7},
      <String, dynamic>{'servicio': 'Tinte', 'total': 5},
    ],
  },
  'dias': <dynamic>[
    <String, dynamic>{
      'fecha': '2026-10-27',
      'total': 2,
      'reservadas': 1,
      'canceladas': 1,
      'completadas': 0,
      'personas': 3,
      'pagos_pendientes': 0,
      'items': <dynamic>[
        <String, dynamic>{
          'id': 41,
          'fecha_hora_reserva': '2026-10-27T10:00:00',
          'cantidad': 1,
          'estado': 'Reservado',
          'id_estado': 1,
          'servicio': 'Corte',
          'local': 'Salon 1',
          'cliente': 'Ana',
          'cliente_telefono': '5355500000',
          'turno': '10:00',
          'motivo_cancelacion': null,
          'pago_estado': null,
          'precio_total': 18,
          'moneda': 'USD',
          'id_local_servicio': 7,
        },
        <String, dynamic>{
          'id': 42,
          'fecha_hora_reserva': '2026-10-27T11:00:00',
          'cantidad': 2,
          'estado': 'Cancelado',
          'id_estado': 2,
          'servicio': 'Tinte',
          'local': 'Salon 1',
          'cliente': 'Luis',
          'turno': '11:00',
          'motivo_cancelacion': 'El cliente no pudo llegar',
          'cancelado_por_rol': 'cliente',
          'pago_estado': 'reportado',
          'precio_total': 25.5,
          'moneda': 'USD',
          'id_local_servicio': 7,
        },
      ],
    },
    <String, dynamic>{
      'fecha': '2026-10-28',
      'total': 0,
      'reservadas': 0,
      'canceladas': 0,
      'completadas': 0,
      'personas': 0,
      'pagos_pendientes': 0,
      'items': <dynamic>[],
    },
  ],
};

void main() {
  setUpAll(() async {
    // `flutter_test_config.dart` no inicializa los símbolos de fecha; sin esto
    // `DateFormat` con `es_ES` revienta. La pantalla lo hace por su cuenta.
    await initializeDateFormatting('es_ES');
  });

  group('ResumenReservas — contrato completo', () {
    test('lee el rango', () {
      final res = ResumenReservas.fromJson(payloadCompleto());

      expect(res.rango.hoy, DateTime(2026, 10, 27));
      expect(res.rango.desde, DateTime(2026, 10, 27));
      expect(res.rango.hasta, DateTime(2027, 3, 31));
      expect(res.rango.ultimoDiaConReserva, DateTime(2027, 3, 14));
      expect(res.rango.truncado, isFalse);
    });

    test('lee el resumen del rango', () {
      final res = ResumenReservas.fromJson(payloadCompleto());

      expect(res.resumen.total, 12);
      expect(res.resumen.reservadas, 6);
      expect(res.resumen.canceladas, 2);
      expect(res.resumen.completadas, 4);
      expect(res.resumen.porServicio, hasLength(2));
      expect(res.resumen.porServicio.first.servicio, 'Corte');
      expect(res.resumen.porServicio.first.total, 7);
      expect(res.estaVacio, isFalse);
    });

    test('lee los días y sus contadores', () {
      final res = ResumenReservas.fromJson(payloadCompleto());

      expect(res.dias, hasLength(2));
      final primero = res.dias.first;
      expect(primero.fecha, DateTime(2026, 10, 27));
      expect(primero.total, 2);
      expect(primero.reservadas, 1);
      expect(primero.canceladas, 1);
      expect(primero.personas, 3);
      expect(primero.pagosPendientes, 0);
      expect(primero.items, hasLength(2));
      expect(primero.tieneReservas, isTrue);
    });

    test('lee los items de un día', () {
      final item = ResumenReservas.fromJson(
        payloadCompleto(),
      ).dias.first.items.first;

      expect(item.id, 41);
      expect(item.fechaHoraReserva, DateTime(2026, 10, 27, 10));
      expect(item.cantidad, 1);
      expect(item.idEstado, 1);
      expect(item.estado, 'Reservado');
      expect(item.servicio, 'Corte');
      expect(item.local, 'Salon 1');
      expect(item.cliente, 'Ana');
      expect(item.clienteTelefono, '5355500000');
      expect(item.turno, '10:00');
      expect(item.motivoCancelacion, isNull);
      expect(item.pagoEstado, isNull);
      expect(item.precioTotal, 18);
      expect(item.moneda, 'USD');
      expect(item.idLocalServicio, 7);
      expect(item.esReservada, isTrue);
      expect(item.tienePagoPendiente, isFalse);
    });

    test('lee el motivo y el pago de una cancelada', () {
      final item = ResumenReservas.fromJson(
        payloadCompleto(),
      ).dias.first.items.last;

      expect(item.id, 42);
      expect(item.esCancelada, isTrue);
      expect(item.motivoCancelacion, 'El cliente no pudo llegar');
      expect(item.canceladoPorRol, 'cliente');
      expect(item.pagoEstado, 'reportado');
      expect(item.tienePagoPendiente, isTrue);
      expect(item.precioTotal, 25.5);
    });

    test('un día sin reservas no cuenta como día del listado', () {
      final res = ResumenReservas.fromJson(payloadCompleto());

      expect(res.dias.last.tieneReservas, isFalse);
      expect(res.diasConReservas, hasLength(1));
      expect(res.diasConReservas.single.fecha, DateTime(2026, 10, 27));
    });

    test('formatea en es_ES sin reventar (necesita initializer)', () {
      final dia = ResumenReservas.fromJson(payloadCompleto()).dias.first;

      final texto = DateFormat('d MMM y', 'es_ES').format(dia.fecha);

      expect(texto, contains('27'));
      expect(texto, contains('oct'));
      expect(texto, contains('2026'));
    });
  });

  group('parseo tolerante — números y textos', () {
    test('enteros como texto', () {
      final res = ResumenReservas.fromJson(<String, dynamic>{
        'resumen': <String, dynamic>{
          'total': '12',
          'reservadas': '6',
          'canceladas': '2',
          'completadas': '4',
        },
        'dias': <dynamic>[
          <String, dynamic>{
            'fecha': '2026-10-27',
            'total': '2',
            'personas': '3',
            'pagos_pendientes': '1',
            'items': <dynamic>[
              <String, dynamic>{
                'id': '41',
                'cantidad': '2',
                'id_estado': '2',
                'precio_total': '18.50',
                'id_local_servicio': '7',
              },
            ],
          },
        ],
      });

      expect(res.resumen.total, 12);
      expect(res.dias.first.total, 2);
      expect(res.dias.first.personas, 3);
      expect(res.dias.first.pagosPendientes, 1);
      final item = res.dias.first.items.first;
      expect(item.id, 41);
      expect(item.cantidad, 2);
      expect(item.idEstado, 2);
      expect(item.precioTotal, 18.5);
      expect(item.idLocalServicio, 7);
    });

    test('enteros con decimales se truncan a int', () {
      final item = ReservaResumen.fromJson(<String, dynamic>{
        'id': 41.0,
        'cantidad': 2.0,
      });

      expect(item.id, 41);
      expect(item.cantidad, 2);
    });

    test('números imposibles no rompen: neutro', () {
      final item = ReservaResumen.fromJson(<String, dynamic>{
        'id': 'abc',
        'cantidad': <dynamic>[],
        'precio_total': 'mucho',
      });

      expect(item.id, 0);
      expect(item.cantidad, 1); // el defecto es 1 persona
      expect(item.precioTotal, isNull);
    });
  });

  group('parseo tolerante — claves ausentes', () {
    test('payload vacío no lanza y da el neutro', () {
      final res = ResumenReservas.fromJson(const <String, dynamic>{});

      expect(res.estaVacio, isTrue);
      expect(res.resumen.total, 0);
      expect(res.dias, isEmpty);
      expect(res.rango.hoy, isNotNull);
      expect(res.rango.truncado, isFalse);
      expect(res.rango.ultimoDiaConReserva, isNull);
    });

    test('null, texto basura y lista se tratan como payload vacío', () {
      expect(ResumenReservas.fromJson(null).dias, isEmpty);
      expect(ResumenReservas.fromJson('no es json').dias, isEmpty);
      expect(ResumenReservas.fromJson(<dynamic>[]).dias, isEmpty);
    });

    test('un día sin items ni contadores', () {
      final dia = DiaResumen.fromJson(<String, dynamic>{'fecha': '2026-10-27'});

      expect(dia.fecha, DateTime(2026, 10, 27));
      expect(dia.total, 0);
      expect(dia.items, isEmpty);
      expect(dia.tieneReservas, isFalse);
      expect(dia.personas, 0);
    });

    test('una reserva sin claves opcionales', () {
      final item = ReservaResumen.fromJson(const <String, dynamic>{});

      expect(item.id, 0);
      expect(item.cantidad, 1);
      expect(item.estado, '');
      expect(item.fechaHoraReserva, isNull);
      expect(item.servicio, isNull);
      expect(item.precioTotal, isNull);
      expect(item.moneda, isNull);
      expect(item.idLocalServicio, isNull);
      expect(item.tienePagoPendiente, isFalse);
    });

    test('textos vacíos se normalizan a null', () {
      final item = ReservaResumen.fromJson(<String, dynamic>{
        'servicio': '   ',
        'moneda': '',
        'cliente': '',
      });

      expect(item.servicio, isNull);
      expect(item.moneda, isNull);
      expect(item.cliente, isNull);
    });

    test('resumen sin por_servicio', () {
      final resumen = TotalesResumen.fromJson(<String, dynamic>{'total': 3});

      expect(resumen.total, 3);
      expect(resumen.porServicio, isEmpty);
      expect(resumen.topServicios(), isEmpty);
      expect(resumen.estaVacio, isFalse);
    });
  });

  group('parseo tolerante — items vacíos y jsonb como texto', () {
    test('items vacíos explícitos', () {
      final dia = DiaResumen.fromJson(<String, dynamic>{
        'fecha': '2026-10-27',
        'total': 1,
        'items': <dynamic>[],
      });

      expect(dia.total, 1);
      expect(dia.items, isEmpty);
    });

    test('items como jsonb en texto', () {
      final dia = DiaResumen.fromJson(<String, dynamic>{
        'fecha': '2026-10-27',
        'total': 1,
        'items': '[{"id":9,"id_estado":3,"servicio":"Tinte","cantidad":2}]',
      });

      expect(dia.items, hasLength(1));
      expect(dia.items.single.id, 9);
      expect(dia.items.single.esCompletada, isTrue);
      expect(dia.items.single.servicio, 'Tinte');
    });

    test('el payload completo como jsonb en texto', () {
      final res = ResumenReservas.fromJson(jsonEncode(payloadCompleto()));

      expect(res.resumen.total, 12);
      expect(res.dias, hasLength(2));
      expect(res.rango.hasta, DateTime(2027, 3, 31));
    });

    test('por_servicio como jsonb en texto', () {
      final resumen = TotalesResumen.fromJson(<String, dynamic>{
        'total': 2,
        'por_servicio': '[{"servicio":"Corte","total":2}]',
      });

      expect(resumen.porServicio, hasLength(1));
      expect(resumen.porServicio.single.servicio, 'Corte');
    });

    test('items con elementos basura se saltan', () {
      final dia = DiaResumen.fromJson(<String, dynamic>{
        'fecha': '2026-10-27',
        'items': <dynamic>[
          null,
          'basura',
          <String, dynamic>{'id': 3},
        ],
      });

      // `null` y el texto suelto no son mapas: solo sobrevive el mapa válido.
      expect(dia.items, hasLength(1));
      expect(dia.items.single.id, 3);
    });
  });

  group('ayudantes del día', () {
    test('soloCanceladas', () {
      final dia = DiaResumen(fecha: _fechaFija, total: 2, canceladas: 2);

      expect(dia.soloCanceladas, isTrue);
      expect(dia.todoCompletado, isFalse);
    });

    test('todoCompletado', () {
      final dia = DiaResumen(fecha: _fechaFija, total: 3, completadas: 3);

      expect(dia.todoCompletado, isTrue);
      expect(dia.soloCanceladas, isFalse);
    });

    test('un día mixto no es ni solo canceladas ni todo completado', () {
      final dia = DiaResumen(
        fecha: _fechaFija,
        total: 3,
        reservadas: 1,
        canceladas: 1,
        completadas: 1,
      );

      expect(dia.soloCanceladas, isFalse);
      expect(dia.todoCompletado, isFalse);
      expect(dia.activas, 2);
    });

    test('pagos pendientes', () {
      final dia = DiaResumen(fecha: _fechaFija, total: 1, pagosPendientes: 1);

      expect(dia.hayPagosPendientes, isTrue);
    });

    test('un día sin datos no dispara nada', () {
      final dia = DiaResumen(fecha: _fechaFija);

      expect(dia.tieneReservas, isFalse);
      expect(dia.soloCanceladas, isFalse);
      expect(dia.todoCompletado, isFalse);
      expect(dia.hayPagosPendientes, isFalse);
    });
  });

  group('ayudantes de la reserva', () {
    test('estados', () {
      expect(const ReservaResumen(id: 1, idEstado: 1).esReservada, isTrue);
      expect(const ReservaResumen(id: 1, idEstado: 2).esCancelada, isTrue);
      expect(const ReservaResumen(id: 1, idEstado: 3).esCompletada, isTrue);
      expect(const ReservaResumen(id: 1).esReservada, isFalse);
    });

    test('pago pendiente incluye reportado y rechazado, no verificado', () {
      expect(
        const ReservaResumen(id: 1, pagoEstado: 'pendiente').tienePagoPendiente,
        isTrue,
      );
      expect(
        const ReservaResumen(id: 1, pagoEstado: 'reportado').tienePagoPendiente,
        isTrue,
      );
      expect(
        const ReservaResumen(id: 1, pagoEstado: 'rechazado').tienePagoPendiente,
        isTrue,
      );
      expect(
        const ReservaResumen(
          id: 1,
          pagoEstado: 'verificado',
        ).tienePagoPendiente,
        isFalse,
      );
      expect(const ReservaResumen(id: 1).tienePagoPendiente, isFalse);
    });

    test('cantidad nunca baja de 1 persona', () {
      expect(const ReservaResumen(id: 1, cantidad: 0).personas, 1);
      expect(const ReservaResumen(id: 1, cantidad: -3).personas, 1);
      expect(const ReservaResumen(id: 1, cantidad: 4).personas, 4);
    });
  });

  group('rango tolerante', () {
    test('truncado acepta bool y texto', () {
      expect(
        RangoReservas.fromJson(<String, dynamic>{
          'hoy': '2026-10-27',
          'truncado': true,
        }).truncado,
        isTrue,
      );
      expect(
        RangoReservas.fromJson(<String, dynamic>{
          'hoy': '2026-10-27',
          'truncado': 'true',
        }).truncado,
        isTrue,
      );
    });

    test('hasta anterior a desde se ancla en desde', () {
      final rango = RangoReservas.fromJson(<String, dynamic>{
        'hoy': '2026-10-27',
        'desde': '2026-10-27',
        'hasta': '2026-10-01',
      });

      expect(rango.hasta, DateTime(2026, 10, 27));
    });

    test('sin rango usa hoy como ancla', () {
      final rango = RangoReservas.fromJson(const <String, dynamic>{});
      final ahora = DateTime.now();

      expect(rango.hoy.year, ahora.year);
      expect(rango.hoy.month, ahora.month);
      expect(rango.hoy.day, ahora.day);
      expect(rango.desde, rango.hoy);
      expect(rango.hasta, rango.hoy);
      expect(rango.hoy.hour, 0);
    });

    test('ultimo_dia_con_reserva ausente es null', () {
      final rango = RangoReservas.fromJson(<String, dynamic>{
        'hoy': '2026-10-27',
        'desde': '2026-10-27',
        'hasta': '2026-10-31',
      });

      expect(rango.ultimoDiaConReserva, isNull);
    });
  });

  group('topServicios', () {
    final resumen = TotalesResumen.fromJson(<String, dynamic>{
      'total': 10,
      'por_servicio': <dynamic>[
        <String, dynamic>{'servicio': 'Corte', 'total': 5},
        <String, dynamic>{'servicio': 'Tinte', 'total': 3},
        <String, dynamic>{'servicio': 'Peinado', 'total': 2},
      ],
    });

    test('tres por defecto', () {
      expect(resumen.topServicios(), hasLength(3));
    });

    test('recorta al número pedido', () {
      final top = resumen.topServicios(2);

      expect(top, hasLength(2));
      expect(top.first.servicio, 'Corte');
      expect(top.last.servicio, 'Tinte');
    });

    test('no recorta si hay menos', () {
      expect(resumen.topServicios(10), hasLength(3));
    });

    test('cero devuelve lista vacía', () {
      expect(resumen.topServicios(0), isEmpty);
    });
  });

  group('diasConReservas', () {
    test('filtra los días a cero y ordena por fecha', () {
      final res = ResumenReservas.fromJson(<String, dynamic>{
        'dias': <dynamic>[
          <String, dynamic>{'fecha': '2026-11-05', 'total': 1},
          <String, dynamic>{'fecha': '2026-10-28', 'total': 0},
          <String, dynamic>{'fecha': '2026-10-27', 'total': 2},
        ],
      });

      final dias = res.diasConReservas;

      expect(dias, hasLength(2));
      expect(dias.first.fecha, DateTime(2026, 10, 27));
      expect(dias.last.fecha, DateTime(2026, 11, 5));
    });

    test('devuelve una lista nueva cada vez', () {
      final res = ResumenReservas.fromJson(payloadCompleto());

      expect(identical(res.diasConReservas, res.diasConReservas), isFalse);
    });
  });
}

/// Fecha constante (no `const`: `DateTime` no tiene constructor constante)
/// para los constructores de los tests.
final DateTime _fechaFija = DateTime(2026, 10, 27);
